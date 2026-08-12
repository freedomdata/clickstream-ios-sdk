import Foundation

/**
 Управляет жизненным циклом пользовательской сессии.
 */
internal final class SessionManager {

    private let queue = DispatchQueue(label: "com.clickstream.sdk.session", qos: .utility)

    /**
     Таймаут пользовательской сессии в миллисекундах.
     */
    private let sessionTimeoutMs: TimeInterval

    /**
     Хранилище состояния пользовательской сессии.
     */
    private let storage: SessionStorage

    /**
     Замыкание для отправки обычных событий сессии.
     */
    private let eventSender: (String, [String: Any]) -> Void

    /**
     Замыкание для отправки критических событий сессии.
     */
    private let criticalEventSender: (String, [String: Any], @escaping @Sendable (Bool) -> Void) -> Void

    /**
     Текущий идентификатор активной сессии.
     */
    private var sessionId: String? = nil

    /**
     Время последней активности пользователя.
     */
    private var lastActiveTime: TimeInterval = 0

    /**
     Время последнего перехода приложения в background.
     */
    private var lastBackgroundTime: TimeInterval? = nil

    /**
     Создает менеджер пользовательской сессии.
     - Parameters:
       - sessionTimeoutMs: Таймаут сессии в миллисекундах.
       - storage: Хранилище состояния пользовательской сессии.
       - eventSender: Замыкание для отправки обычных событий сессии.
       - criticalEventSender: Замыкание для отправки критических событий сессии.
     */
    init(
        sessionTimeoutMs: TimeInterval,
        storage: SessionStorage,
        eventSender: @escaping (String, [String: Any]) -> Void,
        criticalEventSender: @escaping (String, [String: Any], @escaping @Sendable (Bool) -> Void) -> Void
    ) {
        self.sessionTimeoutMs = sessionTimeoutMs
        self.storage = storage
        self.eventSender = eventSender
        self.criticalEventSender = criticalEventSender
    }

    /**
     Гарантирует наличие активной пользовательской сессии.
     */
    func ensureSession() {
        let sessionStarted: String? = queue.sync {
            let now = Date().timeIntervalSince1970 * 1000
            var startedSessionId: String? = nil
            if sessionId == nil {
                let newSession = UUID().uuidString
                sessionId = newSession
                lastActiveTime = now
                startedSessionId = newSession
                storage.saveSession(sessionId: newSession, lastActiveTime: lastActiveTime)
            } else if now - lastActiveTime > sessionTimeoutMs {
                let newSession = UUID().uuidString
                sessionId = newSession
                lastActiveTime = now
                startedSessionId = newSession
                storage.saveSession(sessionId: newSession, lastActiveTime: lastActiveTime)
            } else {
                lastActiveTime = now
                if let id = sessionId {
                    storage.saveSession(sessionId: id, lastActiveTime: lastActiveTime)
                }
            }

            return startedSessionId
        }

        if let started = sessionStarted {
            let lastActive = queue.sync { lastActiveTime }
            storage.saveSession(sessionId: started, lastActiveTime: lastActive)
            eventSender("session_start", ["sessionId": started])
        }
    }

    /**
     Обрабатывает переход приложения в foreground.
     */
    func onForeground() {
        queue.sync {
            let now = Date().timeIntervalSince1970 * 1000
            let backgroundTime = lastBackgroundTime ?? storage.getLastBackgroundTime()
            guard let backgroundTime else { return }
            guard sessionId != nil else {
                lastBackgroundTime = nil
                storage.clearLastBackgroundTime()
                return
            }

            if now - backgroundTime >= sessionTimeoutMs {
                sessionId = nil
                lastActiveTime = 0
                storage.clear()
            }
            lastBackgroundTime = nil
            storage.clearLastBackgroundTime()
        }
        ensureSession()
    }

    /**
     Обрабатывает переход приложения в background.
     */
    func onBackground() {
        queue.sync {
            let now = Date().timeIntervalSince1970 * 1000
            lastActiveTime = now
            lastBackgroundTime = now
            storage.saveLastBackgroundTime(now)
            storage.setPendingAppClose(true)
            if let id = sessionId {
                storage.saveSession(sessionId: id, lastActiveTime: lastActiveTime)
            }
        }
    }

    /**
     Возвращает дату последнего перехода приложения в background.
     - Returns: Дата последнего перехода в background или nil.
     */
    func getLastBackgroundEventDate() -> String? {
        let ms: TimeInterval? = queue.sync {
            lastBackgroundTime ?? storage.getLastBackgroundTime()
        }
        guard let ms else { return nil }
        return TimeUtils.formatWithOffset(date: Date(timeIntervalSince1970: ms / 1000))
    }

    /**
     Восстанавливает дату незавершенного события app_close при необходимости.
     - Returns: Дата события app_close или nil.
     */
    func recoverPendingAppCloseEventDateIfNeeded() -> String? {
        let eventDate: String? = queue.sync {
            guard storage.isPendingAppClose() else { return nil }
            guard let ms = storage.getLastBackgroundTime() else { return nil }
            storage.clearPendingAppClose()
            return TimeUtils.formatWithOffset(date: Date(timeIntervalSince1970: ms / 1000))
        }
        return eventDate
    }

    /**
     Очищает признак ожидающего события app_close.
     */
    func clearPendingAppClose() {
        queue.sync {
            storage.clearPendingAppClose()
        }
    }

    /**
     Завершает текущую сессию при закрытии приложения.
     - Parameters:
       - completion: Замыкание с результатом отправки события завершения сессии.
     */
    func onTerminate(completion: (@Sendable (Bool) -> Void)? = nil) {
        let sessionToEnd: String? = queue.sync {
            let currentSession = sessionId
            sessionId = nil
            lastBackgroundTime = nil
            storage.clearLastBackgroundTime()
            storage.clearPendingAppClose()
            storage.clear()
            return currentSession
        }
        if let ended = sessionToEnd {
            criticalEventSender("session_end", ["sessionId": ended]) { success in
                completion?(success)
            }
        } else {
            completion?(true)
        }
    }

    /**
     Возвращает текущий идентификатор сессии.
     - Returns: Текущий sessionId или nil.
     */
    func getSessionId() -> String? {
        queue.sync { sessionId }
    }

    /**
     Восстанавливает незавершенную сессию из хранилища при необходимости.
     */
    func recoverSessionIfNeeded() {
        guard storage.didStartSession(), storage.getSessionId() != nil else { return }

        storage.clear()
    }
}