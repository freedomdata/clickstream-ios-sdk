import Foundation

/**
 Предоставляет уникальный идентификатор устройства.
 */
internal final class DeviceIdProvider {

    private static let deviceIdKey = "kz.clickstream.sdk.deviceId"

    /**
     Возвращает сохраненный deviceId или создает новый.
     - Returns: Уникальный идентификатор устройства.
     */
    func getDeviceId() -> String {
        if let savedId = UserDefaults.standard.string(forKey: DeviceIdProvider.deviceIdKey) {
            return savedId
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: DeviceIdProvider.deviceIdKey)
        return newId
    }
}