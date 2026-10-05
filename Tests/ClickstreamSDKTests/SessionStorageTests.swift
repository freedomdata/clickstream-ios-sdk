import XCTest
@testable import ClickstreamSDK

/**
 Проверяет сохранение данных сессии в UserDefaults.
 */
final class SessionStorageTests: XCTestCase {
    private var storage: SessionStorage!

    /**
     Подготавливает чистое хранилище сессии перед каждым тестом.
     */
    override func setUp() {
        super.setUp()
        storage = SessionStorage()
        storage.clear()
    }

    /**
     Проверяет сохранение и получение идентификатора сессии.
     */
    func test_saveAndGetSessionId() {
        storage.saveSession(sessionId: "sid-123", lastActiveTime: 100)
        XCTAssertEqual(storage.getSessionId(), "sid-123")
    }

    /**
     Проверяет получение времени последней активности.
     */
    func test_getLastActiveTime() {
        storage.saveSession(sessionId: "sid", lastActiveTime: 999.5)
        XCTAssertEqual(storage.getLastActiveTime(), 999.5)
    }

    /**
     Проверяет удаление сохраненной сессии.
     */
    func test_clear_removesSession() {
        storage.saveSession(sessionId: "sid", lastActiveTime: 100)
        storage.clear()
        XCTAssertNil(storage.getSessionId())
        XCTAssertEqual(storage.getLastActiveTime(), 0)
    }
}