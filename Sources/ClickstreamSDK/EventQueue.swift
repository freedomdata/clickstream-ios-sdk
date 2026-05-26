@preconcurrency import Dispatch
import Foundation

/**
 Управляет offline-очередью событий и их отправкой.
 */
internal final class EventQueue {

    private let ioQueue = DispatchQueue(label: "com.clickstream.sdk.eventqueue", qos: .utility)
    private let store: OfflineEventStore
    private let apiClient: EventApiClient

    private let maxQueueSize: Int
    private let flushQueueSize: Int
    private let flushMaxRetries: Int
    private let flushBatchSize: Int
    private let flushIntervalMillis: TimeInterval
    private let maxFlushProcessingTimeMs: TimeInterval

    private var isFlushing = false
    private var sentInCurrentFlush: Int = 0
    private var flushBatchStart: Date?
    private var periodicWorkItem: DispatchWorkItem?

    /**
     Создает очередь событий с настройками хранения и отправки.
     - Parameters:
       - apiClient: Клиент для отправки событий.
       - maxQueueSize: Максимальный размер offline-очереди.
       - flushQueueSize: Количество событий для автоматического запуска flush.
       - flushMaxRetries: Максимальное количество повторных попыток отправки.
       - flushBatchSize: Максимальное количество отправленных событий за один проход flush.
       - flushIntervalMillis: Интервал периодического flush в миллисекундах.
       - maxFlushProcessingTimeMs: Максимальное время одного прохода flush в миллисекундах.
     */
    init(
        apiClient: EventApiClient,
        maxQueueSize: Int,
        flushQueueSize: Int,
        flushMaxRetries: Int,
        flushBatchSize: Int,
        flushIntervalMillis: TimeInterval,
        maxFlushProcessingTimeMs: TimeInterval
    ) {
        self.apiClient = apiClient
        self.maxQueueSize = maxQueueSize
        self.flushQueueSize = flushQueueSize
        self.flushMaxRetries = flushMaxRetries
        self.flushBatchSize = max(1, flushBatchSize)
        self.flushIntervalMillis = flushIntervalMillis
        self.maxFlushProcessingTimeMs = maxFlushProcessingTimeMs
        self.store = OfflineEventStore(maxEvents: maxQueueSize)

        if !store.isEmpty {
            let work = DispatchWorkItem { [weak self] in
                self?.startFlush()
            }
            ioQueue.async(execute: work)
        }
        schedulePeriodicFlushIfNeeded()
    }

    /**
     Добавляет событие в очередь и запускает flush при достижении порога.
     - Parameters:
       - payload: Данные события для добавления в очередь.
     */
    func enqueue(_ payload: [String: Any]) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let newSize = self.store.add(payload: payload)
            if newSize >= self.flushQueueSize {
                self.startFlush()
            }
        }
        ioQueue.async(execute: work)
    }

    /**
     Запускает ручную отправку накопленных событий.
     */
    func flush() {
        let work = DispatchWorkItem { [weak self] in
            self?.startFlush()
        }
        ioQueue.async(execute: work)
    }

    /**
     Планирует периодическую отправку очереди при включенном интервале.
     */
    private func schedulePeriodicFlushIfNeeded() {
        guard flushIntervalMillis > 0 else { return }
        periodicWorkItem?.cancel()
        let intervalSec = flushIntervalMillis / 1000.0
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.store.isEmpty {
                self.startFlush()
            }
            self.schedulePeriodicFlushIfNeeded()
        }
        periodicWorkItem = work
        ioQueue.asyncAfter(deadline: .now() + intervalSec, execute: work)
    }

    /**
     Запускает отправку очереди, если flush еще не выполняется.
     */
    private func startFlush() {
        guard !isFlushing else { return }
        guard !store.isEmpty else { return }
        guard NetworkMonitor.isNetworkAvailable() else {
            ClickstreamLogger.log("Flush skipped: network unavailable")
            return
        }
        isFlushing = true
        sentInCurrentFlush = 0
        flushBatchStart = Date()
        sendHead()
    }

    /**
     Проверяет, нужно ли перенести остаток очереди на следующий проход flush.
     - Returns: Флаг необходимости прервать текущий проход flush.
     */
    private func shouldYieldBatch() -> Bool {
        guard let start = flushBatchStart else { return false }
        if sentInCurrentFlush >= flushBatchSize { return true }
        return Date().timeIntervalSince(start) * 1000.0 >= maxFlushProcessingTimeMs
    }

    /**
     Завершает текущий проход flush и при необходимости запускает следующий.
     */
    private func finishBatchAndMaybeContinue() {
        guard !store.isEmpty else {
            isFlushing = false
            flushBatchStart = nil
            sentInCurrentFlush = 0
            return
        }
        if shouldYieldBatch() {
            isFlushing = false
            flushBatchStart = nil
            sentInCurrentFlush = 0
            let w = DispatchWorkItem { [weak self] in
                self?.startFlush()
            }
            ioQueue.async(execute: w)
            return
        }
        sendHead()
    }

    /**
     Отправляет первое событие из очереди.
     */
    fileprivate func sendHead() {
        guard NetworkMonitor.isNetworkAvailable() else {
            isFlushing = false
            flushBatchStart = nil
            sentInCurrentFlush = 0
            return
        }
        guard let event = store.peek() else {
            isFlushing = false
            flushBatchStart = nil
            sentInCurrentFlush = 0
            return
        }
        guard event.attempts < flushMaxRetries else {
            store.removeFirst()
            sentInCurrentFlush += 1
            ClickstreamLogger.log("Dropped event: max retries (\(flushMaxRetries)) reached for head event.")
            finishBatchAndMaybeContinue()
            return
        }

        guard let payload = try? JSONSerialization.jsonObject(with: event.payloadData) as? [String: Any] else {
            store.removeFirst()
            ClickstreamLogger.log("Skipped corrupted event")
            finishBatchAndMaybeContinue()
            return
        }

        let uuid = event.uuid
        let maxRetries = flushMaxRetries
        let ioQ = ioQueue
        let handle = EventQueueHandle(self)

        apiClient.sendEvent(payload) { result in
            handle.deliver(
                SendHeadResponse(
                    result: result,
                    uuid: uuid,
                    attempts: event.attempts,
                    maxRetries: maxRetries
                ),
                on: ioQ
            )
        }
    }

    /**
     Обрабатывает результат отправки head-события на ioQueue.
     - Parameters:
       - response: Результат отправки и метаданные события.
     */
    fileprivate func handleSendResponse(_ response: SendHeadResponse) {
        let decision = RetryOrchestrator.evaluate(
            sendResult: response.result,
            currentAttempts: response.attempts,
            maxRetries: response.maxRetries
        )
        switch decision.action {
        case .remove:
            store.removeFirst()
            sentInCurrentFlush += 1
            if case .nonRetryableFailure = response.result {
                ClickstreamLogger.log("Dropped non-retryable event")
            }
            finishBatchAndMaybeContinue()
        case .drop:
            store.removeFirst()
            sentInCurrentFlush += 1
            ClickstreamLogger.log("Dropped event: max retries (\(response.maxRetries)) reached.")
            finishBatchAndMaybeContinue()
        case .retry:
            store.updateAttempts(uuid: response.uuid, newAttempts: decision.nextAttempts)
            let delay = decision.delaySeconds ?? RetryPolicy.backoffDelaySeconds(attemptIndex: response.attempts)
            let roundedDelay = (delay * 100).rounded() / 100
            ClickstreamLogger.log("Send failed. Retry \(decision.nextAttempts)/\(response.maxRetries) in \(roundedDelay)s")
            let handle = EventQueueHandle(self)
            ioQueue.asyncAfter(deadline: .now() + delay) { [handle] in
                handle.resumeSendHead()
            }
        }
    }
}

/**
 Хранит результат отправки head-события для обработки на ioQueue.
 */
private struct SendHeadResponse: Sendable {
    let result: EventApiClient.QueueSendResult
    let uuid: String
    let attempts: Int
    let maxRetries: Int
}

/**
 Передает результат отправки обратно в EventQueue без захвата non-Sendable self.
 */
private final class EventQueueHandle: Sendable {
    nonisolated(unsafe) private weak var queue: EventQueue?

    init(_ queue: EventQueue) {
        self.queue = queue
    }

    /**
     Доставляет результат отправки на serial queue EventQueue.
     - Parameters:
       - response: Результат отправки и метаданные события.
       - ioQ: Serial queue EventQueue.
     */
    func deliver(_ response: SendHeadResponse, on ioQ: DispatchQueue) {
        ioQ.async { [self] in
            queue?.handleSendResponse(response)
        }
    }

    /**
     Возобновляет отправку head-события на ioQueue EventQueue.
     */
    func resumeSendHead() {
        queue?.sendHead()
    }
}