import Foundation

/**
 Управляет хранением данных сессии в UserDefaults.
 */
internal final class SessionStorage {

    private static let sessionIdKey = "kz.clickstream.sdk.sessionId"
    private static let lastActiveTimeKey = "kz.clickstream.sdk.lastActiveTime"
    private static let lastBackgroundTimeKey = "kz.clickstream.sdk.lastBackgroundTime"
    private static let pendingAppCloseKey = "kz.clickstream.sdk.pendingAppClose"
    private static let didStartSessionKey = "kz.clickstream.sdk.didStartSession"

    /**
     Сохраняет идентификатор сессии и время последней активности.
     - Parameters:
       - sessionId: Идентификатор текущей сессии.
       - lastActiveTime: Время последней активности.
     */
    func saveSession(sessionId: String, lastActiveTime: TimeInterval) {
        UserDefaults.standard.set(sessionId, forKey: SessionStorage.sessionIdKey)
        UserDefaults.standard.set(lastActiveTime, forKey: SessionStorage.lastActiveTimeKey)
        UserDefaults.standard.set(true, forKey: SessionStorage.didStartSessionKey)
    }

    /**
     Возвращает текущий идентификатор сессии.
     - Returns: Идентификатор сессии или nil.
     */
    func getSessionId() -> String? {
        UserDefaults.standard.string(forKey: SessionStorage.sessionIdKey)
    }

    /**
     Возвращает время последней активности сессии.
     - Returns: Время последней активности.
     */
    func getLastActiveTime() -> TimeInterval {
        UserDefaults.standard.double(forKey: SessionStorage.lastActiveTimeKey)
    }

    /**
     Проверяет, была ли начата сессия.
     - Returns: Флаг наличия начатой сессии.
     */
    func didStartSession() -> Bool {
        UserDefaults.standard.bool(forKey: SessionStorage.didStartSessionKey)
    }

    /**
     Сохраняет время последнего перехода приложения в background.
     - Parameters:
       - timeMs: Время перехода в background в миллисекундах.
     */
    func saveLastBackgroundTime(_ timeMs: TimeInterval) {
        UserDefaults.standard.set(timeMs, forKey: SessionStorage.lastBackgroundTimeKey)
    }

    /**
     Возвращает время последнего перехода приложения в background.
     - Returns: Время перехода в background в миллисекундах или nil.
     */
    func getLastBackgroundTime() -> TimeInterval? {
        let v = UserDefaults.standard.object(forKey: SessionStorage.lastBackgroundTimeKey) as? NSNumber
        return v?.doubleValue
    }

    /**
     Очищает время последнего перехода приложения в background.
     */
    func clearLastBackgroundTime() {
        UserDefaults.standard.removeObject(forKey: SessionStorage.lastBackgroundTimeKey)
    }

    /**
     Сохраняет признак ожидающего события app_close.
     - Parameters:
       - pending: Флаг ожидающего события app_close.
     */
    func setPendingAppClose(_ pending: Bool) {
        UserDefaults.standard.set(pending, forKey: SessionStorage.pendingAppCloseKey)
    }

    /**
     Проверяет наличие ожидающего события app_close.
     - Returns: Флаг ожидающего события app_close.
     */
    func isPendingAppClose() -> Bool {
        UserDefaults.standard.bool(forKey: SessionStorage.pendingAppCloseKey)
    }

    /**
     Очищает признак ожидающего события app_close.
     */
    func clearPendingAppClose() {
        UserDefaults.standard.removeObject(forKey: SessionStorage.pendingAppCloseKey)
    }

    /**
     Очищает все сохраненные данные сессии.
     */
    func clear() {
        UserDefaults.standard.removeObject(forKey: SessionStorage.sessionIdKey)
        UserDefaults.standard.removeObject(forKey: SessionStorage.lastActiveTimeKey)
        UserDefaults.standard.removeObject(forKey: SessionStorage.lastBackgroundTimeKey)
        UserDefaults.standard.removeObject(forKey: SessionStorage.pendingAppCloseKey)
        UserDefaults.standard.removeObject(forKey: SessionStorage.didStartSessionKey)
    }
}