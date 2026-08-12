import Foundation

/**
 Контракт локального хранения конфигурации флагов.
 */
internal protocol FlagStoring: AnyObject {
    /**
     Сохраняет конфигурацию флагов для устройства.
     - Parameters:
       - flags: Конфигурация флагов.
       - deviceId: Идентификатор устройства.
     - Returns: true, если сериализация прошла и запись подтверждена read-back из UserDefaults.
     */
    func save(flags: [FlagInfo], deviceId: String) -> Bool

    /**
     Возвращает сохраненную конфигурацию флагов для устройства.
     - Parameters:
       - deviceId: Идентификатор устройства.
     - Returns: Сохраненная конфигурация флагов или nil.
     */
    func load(deviceId: String) -> [FlagInfo]?

    /**
     Сохраняет отложенную конфигурацию флагов для повторной записи после restart.
     - Parameters:
       - flags: Конфигурация флагов.
       - deviceId: Идентификатор устройства.
     - Returns: true, если сериализация прошла и запись подтверждена read-back из UserDefaults.
     */
    func savePending(flags: [FlagInfo], deviceId: String) -> Bool

    /**
     Возвращает отложенную конфигурацию флагов для устройства.
     - Parameters:
       - deviceId: Идентификатор устройства.
     - Returns: Отложенная конфигурация флагов или nil.
     */
    func loadPending(deviceId: String) -> [FlagInfo]?

    /**
     Удаляет отложенную конфигурацию флагов для устройства.
     - Parameter deviceId: Идентификатор устройства.
     */
    func clearPending(deviceId: String)
}

/**
 Сохраняет последнюю успешно полученную конфигурацию флагов.
 */
internal final class FlagStorage: FlagStoring {

    private static let keyPrefix = "kz.clickstream.sdk.flags."
    private static let pendingKeyPrefix = "kz.clickstream.sdk.flags.pending."

    /**
     Сохраняет конфигурацию флагов для устройства.
     - Parameters:
       - flags: Конфигурация флагов.
       - deviceId: Идентификатор устройства.
     - Returns: true, если сериализация прошла и запись подтверждена read-back из UserDefaults.
     */
    func save(flags: [FlagInfo], deviceId: String) -> Bool {
        guard let data = try? JSONEncoder().encode(flags) else {
            ClickstreamLogger.log("Failed to serialize flags for local storage.")
            return false
        }
        let key = Self.keyPrefix + deviceId
        guard persist(data: data, forKey: key, failureLogMessage: "Failed to persist flags in UserDefaults.") else {
            return false
        }
        clearPending(deviceId: deviceId)
        return true
    }

    func load(deviceId: String) -> [FlagInfo]? {
        guard let data = UserDefaults.standard.data(forKey: Self.keyPrefix + deviceId) else {
            return nil
        }
        return decodeFlags(from: data)
    }

    func savePending(flags: [FlagInfo], deviceId: String) -> Bool {
        guard let data = try? JSONEncoder().encode(flags) else {
            ClickstreamLogger.log("Failed to serialize pending flags for local storage.")
            return false
        }
        let key = Self.pendingKeyPrefix + deviceId
        return persist(
            data: data,
            forKey: key,
            failureLogMessage: "Failed to persist pending flags in UserDefaults."
        )
    }

    func loadPending(deviceId: String) -> [FlagInfo]? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingKeyPrefix + deviceId) else {
            return nil
        }
        return decodeFlags(from: data)
    }

    func clearPending(deviceId: String) {
        UserDefaults.standard.removeObject(forKey: Self.pendingKeyPrefix + deviceId)
    }

    /**
     Возвращает наиболее актуальную сохраненную конфигурацию флагов.
     - Parameter deviceId: Идентификатор устройства.
     - Returns: Отложенная или основная конфигурация флагов.
     */
    func loadBestAvailable(deviceId: String) -> [FlagInfo]? {
        loadPending(deviceId: deviceId) ?? load(deviceId: deviceId)
    }

    private func decodeFlags(from data: Data) -> [FlagInfo]? {
        guard let flags = try? JSONDecoder().decode([FlagInfo].self, from: data) else {
            ClickstreamLogger.log("Failed to decode stored flags configuration.")
            return nil
        }
        return flags
    }

    /**
     Записывает данные в UserDefaults и подтверждает успех read-back.
     - Parameters:
       - data: Сериализованные данные.
       - key: Ключ UserDefaults.
       - failureLogMessage: Сообщение при неудачной записи.
     - Returns: true, если read-back совпал с записанными данными.
     */
    private func persist(data: Data, forKey key: String, failureLogMessage: String) -> Bool {
        UserDefaults.standard.set(data, forKey: key)
        guard let readBack = UserDefaults.standard.data(forKey: key), readBack == data else {
            ClickstreamLogger.log(failureLogMessage)
            return false
        }
        return true
    }
}
