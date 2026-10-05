import XCTest
@testable import ClickstreamSDK

/**
 Проверяет управление жизненным циклом пользовательской сессии.
 */
final class SessionManagerTests: XCTestCase {
    private var storage: SessionStorage!
    private var sentEvents: [(String, [String: Any])]!

    /**
     Подготавливает чистое хранилище и список событий перед каждым тестом.
     */
    override func setUp() {
        super.setUp()
        storage = SessionStorage()
        storage.clear()
        sentEvents = []
    }

    /**
     Создает SessionManager с тестовыми обработчиками событий.
     - Parameters:
       - timeoutMs: Таймаут сессии в миллисекундах.
     - Returns: Экземпляр SessionManager для теста.
     */
    private func makeManager(timeoutMs: TimeInterval = 60_000) -> SessionManager {
        SessionManager(
            sessionTimeoutMs: timeoutMs,
            storage: storage,
            eventSender: { name, payload in self.sentEvents.append((name, payload)) },
            criticalEventSender: { name, payload, completion in
                self.sentEvents.append((name, payload))
                completion(true)
            }
        )
    }

    /**
     Проверяет отправку session_start при создании сессии.
     */
    func test_ensureSession_sendsSessionStart() {
        let manager = makeManager()
        manager.ensureSession()
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents[0].0, "session_start")
        XCTAssertNotNil(sentEvents[0].1["sessionId"])
    }

    /**
     Проверяет возврат sessionId после создания сессии.
     */
    func test_getSessionId_returnsIdAfterEnsureSession() {
        let manager = makeManager()
        manager.ensureSession()
        let sessionId = manager.getSessionId()
        XCTAssertNotNil(sessionId)
        XCTAssertEqual(sessionId, sentEvents[0].1["sessionId"] as? String)
    }

    /**
     Проверяет очистку сохраненной сессии без отправки событий.
     */
    func test_recoverSessionIfNeeded_clearsStoredSessionWithoutSendingEvents() {
        storage.saveSession(sessionId: "orphan-session", lastActiveTime: Date().timeIntervalSince1970 * 1000)
        let manager = makeManager()
        manager.recoverSessionIfNeeded()
        XCTAssertTrue(sentEvents.isEmpty)
        XCTAssertNil(storage.getSessionId())
        XCTAssertFalse(storage.didStartSession())
    }

    /**
     Проверяет отсутствие восстановления без признака начатой сессии.
     */
    func test_recoverSessionIfNeeded_doesNothingWhenSessionWasNotStartedFlagMissing() {
        UserDefaults.standard.set("orphan-session", forKey: "kz.clickstream.sdk.sessionId")
        let manager = makeManager()
        manager.recoverSessionIfNeeded()
        XCTAssertTrue(sentEvents.isEmpty)
    }

    /**
     Проверяет отсутствие восстановления при пустом хранилище.
     */
    func test_recoverSessionIfNeeded_doesNothingWhenNoStoredSession() {
        let manager = makeManager()
        manager.recoverSessionIfNeeded()
        XCTAssertTrue(sentEvents.isEmpty)
    }

    /**
     Проверяет смену сессии после истечения таймаута без background.
     */
    func test_ensureSession_afterTimeoutWithoutBackground_rotatesSession() {
        let manager = makeManager(timeoutMs: 5)
        manager.ensureSession()
        XCTAssertEqual(sentEvents.count, 1)
        let firstSessionId = sentEvents[0].1["sessionId"] as? String
        Thread.sleep(forTimeInterval: 0.02)
        manager.ensureSession()
        XCTAssertEqual(sentEvents.count, 2)
        XCTAssertEqual(sentEvents[1].0, "session_start")
        let secondSessionId = manager.getSessionId()
        XCTAssertNotEqual(firstSessionId, secondSessionId)
        XCTAssertEqual(secondSessionId, sentEvents[1].1["sessionId"] as? String)
    }

    /**
     Проверяет отсутствие session_end при возврате из background до таймаута.
     */
    func test_onBackground_thenTimeout_thenForeground_doesNotSendSessionEnd() {
        let manager = SessionManager(
            sessionTimeoutMs: 500,
            storage: storage,
            eventSender: { name, payload in
                self.sentEvents.append((name, payload))
            },
            criticalEventSender: { name, payload, completion in
                self.sentEvents.append((name, payload))
                completion(true)
            }
        )
        manager.ensureSession()
        let sessionIdBefore = manager.getSessionId()
        manager.onBackground()
        Thread.sleep(forTimeInterval: 0.06)
        manager.onForeground()
        XCTAssertFalse(sentEvents.contains { $0.0 == "session_end" })
        XCTAssertEqual(manager.getSessionId(), sessionIdBefore)
        XCTAssertEqual(sentEvents.filter { $0.0 == "session_start" }.count, 1)
    }

    /**
     Проверяет немедленную отправку session_end при завершении приложения.
     */
    func test_onTerminate_sendsSessionEndImmediately() {
        let manager = makeManager(timeoutMs: 60_000)
        manager.ensureSession()
        let sessionId = manager.getSessionId()
        XCTAssertNotNil(sessionId)

        manager.onTerminate()

        XCTAssertEqual(sentEvents.count, 2)
        XCTAssertEqual(sentEvents[1].0, "session_end")
        XCTAssertEqual(sentEvents[1].1["sessionId"] as? String, sessionId)
        XCTAssertNil(manager.getSessionId())
    }
}