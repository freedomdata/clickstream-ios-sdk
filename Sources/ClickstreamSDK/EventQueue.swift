@preconcurrency import Dispatch
import Foundation

/**
 Управляет offline-очередью событий и их пакетной отправкой.
 */
internal final class EventQueue {
    private let ioQueue = DispatchQueue(label: "com.clickstream.sdk.eventqueue", qos: .utility)
    private let store: OfflineEventStore
    private let apiClient: EventApiClient
    private let maxBackoffAttempt: Int
    private let maxBatchSize: Int
    private let flushIntervalMillis: TimeInterval
    private let maxFlushProcessingTimeMs: TimeInterval
    private var isFlushing = false
    private var isDeliveryStopped = false
    private var flushStartedAt: Date?
    private var periodicWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private var firstAttemptCompletions: [String: @Sendable (Bool) -> Void] = [:]

    /**
     Создает очередь событий с настройками хранения и пакетной отправки.
     - Parameters:
       - apiClient: Клиент batch endpoint-а.
       - maxQueueSize: Максимальное количество сохраненных событий.
       - flushMaxRetries: Номер попытки, после которого прекращается рост backoff.
       - flushBatchSize: Максимальное количество событий в batch и порог отправки.
       - flushIntervalMillis: Интервал отправки неполного batch в миллисекундах.
       - maxFlushProcessingTimeMs: Максимальная длительность одного flush-прохода в миллисекундах.
       - fileManager: Файловый менеджер offline-хранилища.
     */
    init(
        apiClient: EventApiClient,
        maxQueueSize: Int,
        flushMaxRetries: Int,
        flushBatchSize: Int,
        flushIntervalMillis: TimeInterval,
        maxFlushProcessingTimeMs: TimeInterval,
        fileManager: FileManager = .default
    ) {
        self.apiClient = apiClient
        self.maxBackoffAttempt = max(1, flushMaxRetries)
        self.maxBatchSize = max(1, flushBatchSize)
        self.flushIntervalMillis = flushIntervalMillis
        self.maxFlushProcessingTimeMs = maxFlushProcessingTimeMs
        self.store = OfflineEventStore(maxEvents: maxQueueSize, fileManager: fileManager)

        if !store.isEmpty {
            ioQueue.async { [weak self] in self?.startFlush() }
        }
    }

    /**
     Добавляет событие в persistent-очередь и при необходимости запускает немедленную отправку.
     - Parameters:
       - payload: Данные события.
       - flushImmediately: Флаг немедленного запуска отправки.
       - firstAttemptCompletion: Замыкание с результатом первой сетевой попытки для события.
     */
    func enqueue(
        _ payload: [String: Any],
        flushImmediately: Bool = false,
        firstAttemptCompletion: (@Sendable (Bool) -> Void)? = nil
    ) {
        ioQueue.async { [weak self] in
            guard let self else { firstAttemptCompletion?(false); return }
            guard let result = self.store.addAndReportDiscarded(payload: payload) else {
                firstAttemptCompletion?(false)
                return
            }
            self.failFirstAttempts(for: result.discardedEventIdentifiers)
            guard !self.isDeliveryStopped else {
                firstAttemptCompletion?(false)
                return
            }
            if let firstAttemptCompletion {
                self.firstAttemptCompletions[result.eventIdentifier] = firstAttemptCompletion
            }
            if flushImmediately || self.store.count >= self.maxBatchSize {
                self.startFlush()
            } else {
                self.schedulePeriodicFlushIfNeeded()
            }
        }
    }

    /**
     Запускает ручную отправку накопленных событий.
     */
    func flush() {
        ioQueue.async { [weak self] in
            guard let self, !self.isDeliveryStopped else { return }
            self.cancelPeriodicTimer()
            self.startFlush()
        }
    }

    /**
     Планирует одноразовую отправку по интервалу от первого события очереди.
     */
    private func schedulePeriodicFlushIfNeeded() {
        guard !isDeliveryStopped,
              flushIntervalMillis > 0,
              !isFlushing,
              !store.isEmpty,
              periodicWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.periodicWorkItem = nil
            if !self.store.isEmpty { self.startFlush() }
        }
        periodicWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + flushIntervalMillis / 1000.0, execute: work)
    }

    /**
     Запускает batch-отправку, если в очереди нет другой активной попытки.
     */
    private func startFlush() {
        guard !isDeliveryStopped, !isFlushing, !store.isEmpty else { return }
        cancelPeriodicTimer()
        retryWorkItem?.cancel()
        retryWorkItem = nil
        isFlushing = true
        flushStartedAt = Date()
        sendNextBatch()
    }

    /**
     Выбирает FIFO batch и отправляет его единственным in-flight запросом.
     */
    private func sendNextBatch() {
        guard isFlushing else { return }
        guard !store.isEmpty else {
            finishFlush()
            return
        }
        let result = store.batchAndReportDiscarded(maxCount: maxBatchSize)
        failFirstAttempts(for: result.discardedEventIdentifiers)
        let events = result.events
        guard !events.isEmpty else {
            finishFlush()
            return
        }
        let handle = EventQueueHandle(self)
        let queue = ioQueue
        apiClient.sendBatch(events.map(\.payloadData)) { result in
            handle.deliver(BatchResponse(result: result, events: events), on: queue)
        }
    }

    /**
     Обрабатывает ответ batch-запроса и подтверждения отдельных событий.
     - Parameter response: Результат запроса и отправленные события.
     */
    func handleBatchResponse(_ response: BatchResponse) {
        switch response.result {
        case let .processed(results):
            let selectedByIndex = Dictionary(uniqueKeysWithValues: response.events.enumerated().map { ($0.offset, $0.element) })
            var terminalUUIDs = Set<String>()
            var terminalIndices = Set<Int>()
            for result in results {
                guard let event = selectedByIndex[result.index] else { continue }
                terminalUUIDs.insert(event.uuid)
                terminalIndices.insert(result.index)
                if result.status == .failed {
                    ClickstreamLogger.log("Batch event failed at index \(result.index): \(result.message ?? "unknown error")")
                }
            }
            store.remove(uuids: terminalUUIDs)
            let pending = response.events.enumerated().compactMap { terminalIndices.contains($0.offset) ? nil : $0.element }
            handleRetryableEvents(pending, retryAfterSeconds: nil)
        case let .retryableFailure(retryAfterSeconds):
            handleRetryableEvents(response.events, retryAfterSeconds: retryAfterSeconds)
        case let .nonRetryableHTTPFailure(statusCode):
            if statusCode == 401 || statusCode == 403 {
                ClickstreamLogger.log("Batch delivery stopped after HTTP \(statusCode)")
                stopDelivery()
            } else {
                ClickstreamLogger.log("Batch request failed with non-retryable error")
                store.remove(uuids: Set(response.events.map(\.uuid)))
                continueFlush()
            }
        case .nonRetryableTransportFailure:
            ClickstreamLogger.log("Batch delivery stopped after non-retryable transport error")
            stopDelivery()
        }
        completeFirstAttempts(for: response)
    }

    /**
     Вызывает ожидающие completion после первой сетевой попытки соответствующих событий.
     - Parameter response: Результат запроса и отправленные события.
     */
    private func completeFirstAttempts(for response: BatchResponse) {
        let successfulIndices: Set<Int>
        switch response.result {
        case let .processed(results):
            successfulIndices = Set(results.compactMap { $0.status == .success ? $0.index : nil })
        case .retryableFailure, .nonRetryableHTTPFailure, .nonRetryableTransportFailure:
            successfulIndices = []
        }
        for (index, event) in response.events.enumerated() {
            firstAttemptCompletions.removeValue(forKey: event.uuid)?(successfulIndices.contains(index))
        }
    }

    /**
     Завершает с ошибкой callbacks событий, удаленных до первой сетевой попытки.
     - Parameter eventIdentifiers: Идентификаторы удаленных событий.
     */
    private func failFirstAttempts(for eventIdentifiers: Set<String>) {
        for eventIdentifier in eventIdentifiers {
            firstAttemptCompletions.removeValue(forKey: eventIdentifier)?(false)
        }
    }

    /**
     Увеличивает attempts и планирует повторную отправку retryable-событий.
     - Parameters:
       - events: События для повторной отправки.
       - retryAfterSeconds: Серверная задержка Retry-After в секундах.
     */
    private func handleRetryableEvents(_ events: [StoredEvent], retryAfterSeconds: TimeInterval?) {
        guard !events.isEmpty else {
            continueFlush()
            return
        }
        let attempts = store.updateAttempts(for: events)
        scheduleRetry(
            attemptIndex: min(attempts, maxBackoffAttempt),
            retryAfterSeconds: retryAfterSeconds
        )
    }

    /**
     Планирует повторную отправку batch с учетом Retry-After или backoff.
     - Parameters:
       - attemptIndex: Номер попытки для расчета backoff.
       - retryAfterSeconds: Серверная задержка Retry-After в секундах.
     */
    private func scheduleRetry(attemptIndex: Int, retryAfterSeconds: TimeInterval?) {
        let delay = retryAfterSeconds ?? RetryPolicy.backoffDelaySeconds(attemptIndex: attemptIndex)
        retryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryWorkItem = nil
            self.sendNextBatch()
        }
        retryWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    /**
     Продолжает обработку очереди после завершения текущего batch.
     */
    private func continueFlush() {
        guard !store.isEmpty else {
            finishFlush()
            return
        }
        if maxFlushProcessingTimeMs > 0,
           let started = flushStartedAt,
           Date().timeIntervalSince(started) * 1000 >= maxFlushProcessingTimeMs {
            isFlushing = false
            flushStartedAt = nil
            schedulePeriodicFlushIfNeeded()
            ioQueue.async { [weak self] in self?.startFlush() }
            return
        }
        sendNextBatch()
    }

    /**
     Завершает flush и оставляет непустую очередь готовой к следующей попытке.
     */
    private func finishFlush() {
        isFlushing = false
        flushStartedAt = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        if !isDeliveryStopped, !store.isEmpty { schedulePeriodicFlushIfNeeded() }
    }

    /**
     Останавливает сетевую доставку и завершает callbacks без удаления сохраненных событий.
     */
    private func stopDelivery() {
        isDeliveryStopped = true
        isFlushing = false
        flushStartedAt = nil
        cancelPeriodicTimer()
        retryWorkItem?.cancel()
        retryWorkItem = nil
        let completions = Array(firstAttemptCompletions.values)
        firstAttemptCompletions.removeAll()
        completions.forEach { $0(false) }
    }

    /**
     Отменяет таймер ожидания неполного batch.
     */
    private func cancelPeriodicTimer() {
        periodicWorkItem?.cancel()
        periodicWorkItem = nil
    }
}
