import Foundation

/**
 Управляет запросом, кэшированием и локальным хранением конфигурации флагов.
 */
internal final class FlagManager {

    private static let maxPersistenceRetries = 5

    private let apiClient: FlagFetching
    private let storage: FlagStoring
    private let deviceId: String
    private let queue = DispatchQueue(label: "com.clickstream.sdk.flags", qos: .utility)
    private var cachedFlags: [FlagInfo]?
    private var persistenceRetryWorkItem: DispatchWorkItem?

    /**
     Создает менеджер конфигурации флагов.
     - Parameters:
       - baseUrl: Базовый URL сервера Clickstream.
       - apiKey: Ключ авторизации для доступа к API.
       - deviceId: Идентификатор устройства.
       - storage: Хранилище локальной конфигурации флагов.
       - apiClient: Клиент для запроса конфигурации флагов.
     */
    init(
        baseUrl: String,
        apiKey: String,
        deviceId: String,
        storage: FlagStoring = FlagStorage(),
        apiClient: FlagFetching? = nil
    ) {
        self.apiClient = apiClient ?? FlagApiClient(baseUrl: baseUrl, apiKey: apiKey)
        self.storage = storage
        self.deviceId = deviceId
        self.cachedFlags = Self.resolveInitialFlags(storage: storage, deviceId: deviceId)

        if storage.loadPending(deviceId: deviceId) != nil {
            queue.async { [weak self] in
                self?.persistCachedFlags(attemptIndex: 0)
            }
        }
    }

    /**
     Возвращает сохраненную конфигурацию флагов из in-memory cache или локального хранилища.
     - Returns: Конфигурация флагов или nil.
     */
    func getFlags() -> [FlagInfo]? {
        queue.sync {
            if let cachedFlags {
                return cachedFlags
            }
            let stored = Self.resolveInitialFlags(storage: storage, deviceId: deviceId)
            cachedFlags = stored
            return stored
        }
    }

    /**
     Запрашивает конфигурацию флагов с backend и обновляет локальный cache при успехе.
     - Parameters:
       - completion: Замыкание с результатом запроса.
     */
    func fetchFlags(completion: @escaping @Sendable (FetchFlagsResult) -> Void) {
        apiClient.fetchFlags(deviceId: deviceId) { [weak self] result in
            guard let self else { return }

            let outcome = self.queue.sync { () -> FetchFlagsResult in
                switch result {
                case .success(let flags):
                    return self.applyFreshFlags(flags)

                case .failure(let error):
                    return self.fallbackOrFailure(error)
                }
            }
            completion(outcome)
        }
    }

    /**
     Применяет свежую конфигурацию флагов в in-memory cache и пытается сохранить ее локально.
     - Parameter flags: Конфигурация флагов, полученная с backend.
     - Returns: Результат запроса с актуальной конфигурацией.
     */
    private func applyFreshFlags(_ flags: [FlagInfo]) -> FetchFlagsResult {
        cachedFlags = flags
        cancelPersistenceRetry()

        if storage.save(flags: flags, deviceId: deviceId) {
            return .success(flags)
        }

        if !storage.savePending(flags: flags, deviceId: deviceId) {
            ClickstreamLogger.log("Failed to persist flags and pending snapshot for device.")
        } else {
            ClickstreamLogger.log("Failed to persist flags. Saved pending snapshot and scheduled retry.")
        }

        schedulePersistenceRetry(attemptIndex: 0)
        return .success(flags)
    }

    /**
     Возвращает fallback из cache или ошибку, если сохраненных флагов нет.
     - Parameter error: Ошибка, возвращаемая при отсутствии cache.
     - Returns: Результат запроса с fallback или ошибкой.
     */
    private func fallbackOrFailure(_ error: FlagsFetchError) -> FetchFlagsResult {
        if let cachedFlags {
            return .fallback(cachedFlags)
        }
        let stored = Self.resolveInitialFlags(storage: storage, deviceId: deviceId)
        if let stored {
            cachedFlags = stored
            return .fallback(stored)
        }
        return .failure(error)
    }

    /**
     Планирует повторную попытку сохранения актуальной конфигурации флагов.
     - Parameter attemptIndex: Индекс текущей попытки сохранения.
     */
    private func schedulePersistenceRetry(attemptIndex: Int) {
        cancelPersistenceRetry()

        guard attemptIndex < Self.maxPersistenceRetries else {
            ClickstreamLogger.log("Failed to persist flags after \(Self.maxPersistenceRetries) attempts.")
            return
        }

        let delay = RetryPolicy.backoffDelaySeconds(attemptIndex: attemptIndex)
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistCachedFlags(attemptIndex: attemptIndex)
        }
        persistenceRetryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /**
     Пытается сохранить актуальную in-memory конфигурацию флагов на диск.
     - Parameter attemptIndex: Индекс текущей попытки сохранения.
     */
    private func persistCachedFlags(attemptIndex: Int) {
        guard let flags = cachedFlags else { return }

        if storage.save(flags: flags, deviceId: deviceId) {
            persistenceRetryWorkItem = nil
            return
        }

        if !storage.savePending(flags: flags, deviceId: deviceId) {
            ClickstreamLogger.log("Failed to update pending flags snapshot during retry.")
        }

        schedulePersistenceRetry(attemptIndex: attemptIndex + 1)
    }

    /**
     Отменяет запланированную повторную попытку сохранения.
     */
    private func cancelPersistenceRetry() {
        persistenceRetryWorkItem?.cancel()
        persistenceRetryWorkItem = nil
    }

    /**
     Возвращает наиболее актуальную локальную конфигурацию флагов.
     - Parameters:
       - storage: Хранилище локальной конфигурации флагов.
       - deviceId: Идентификатор устройства.
     - Returns: Конфигурация флагов или nil.
     */
    private static func resolveInitialFlags(storage: FlagStoring, deviceId: String) -> [FlagInfo]? {
        storage.loadPending(deviceId: deviceId) ?? storage.load(deviceId: deviceId)
    }
}
