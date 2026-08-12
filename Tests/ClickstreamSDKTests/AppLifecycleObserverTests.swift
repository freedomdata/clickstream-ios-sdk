import UIKit
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет обработку событий жизненного цикла приложения.
 */
final class AppLifecycleObserverTests: XCTestCase {

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
     Проверяет отправку session_start при didBecomeActive.
     */
    func test_didBecomeActive_triggersSessionStart() {
        let expectation = expectation(description: "session_start")
        var sentEvents: [String] = []
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { name, _ in
                sentEvents.append(name)
                if name == "session_start" { expectation.fulfill() }
            },
            criticalEventSender: { name, _, completion in
                sentEvents.append(name)
                completion(true)
            }
        )

        let observer = AppLifecycleObserver(sessionManager: sessionManager)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(sentEvents.contains("session_start"), "sentEvents: \(sentEvents)")
        _ = observer
    }

    /**
     Проверяет отправку session_start при willEnterForeground.
     */
    func test_willEnterForeground_triggersSessionStart() {
        let expectation = expectation(description: "session_start")
        var sentEvents: [String] = []
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { name, _ in
                sentEvents.append(name)
                if name == "session_start" { expectation.fulfill() }
            },
            criticalEventSender: { name, _, completion in
                sentEvents.append(name)
                completion(true)
            }
        )

        let observer = AppLifecycleObserver(sessionManager: sessionManager)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(sentEvents.contains("session_start"), "sentEvents: \(sentEvents)")
        _ = observer
    }

    /**
     Проверяет создание observer с SessionManager без падения.
     */
    func test_init_withSessionManager_doesNotCrash() {
        var sentEvents: [String] = []
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { name, _ in sentEvents.append(name) },
            criticalEventSender: { name, _, completion in
                sentEvents.append(name)
                completion(true)
            }
        )
        let observer = AppLifecycleObserver(sessionManager: sessionManager)
        _ = observer
    }

    /**
     Проверяет отсутствие session_end при willResignActive.
     */
    func test_willResignActive_doesNotSendSessionEnd() {
        let sessionStartExp = expectation(description: "session_start")
        var sentEvents: [String] = []
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { name, _ in
                sentEvents.append(name)
                if name == "session_start" { sessionStartExp.fulfill() }
            },
            criticalEventSender: { name, _, completion in
                sentEvents.append(name)
                completion(true)
            }
        )
        let observer = AppLifecycleObserver(sessionManager: sessionManager)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        wait(for: [sessionStartExp], timeout: 2.0)

        sentEvents.removeAll()
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))

        XCTAssertFalse(sentEvents.contains("session_end"), "Inactive must not end session; got: \(sentEvents)")
        _ = observer
    }

    /**
     Проверяет безопасный повторный вызов unsubscribe.
     */
    func test_unsubscribe_doesNotCrash() {
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { _, _ in },
            criticalEventSender: { _, _, completion in
                completion(true)
            }
        )
        let observer = AppLifecycleObserver(sessionManager: sessionManager)
        observer.subscribe()
        observer.unsubscribe()
        observer.unsubscribe()
        _ = observer
    }

    /**
     Проверяет отправку app_close при didEnterBackground.
     */
    func test_didEnterBackground_afterDelay_sendsAppClose() {
        let appCloseExp = expectation(description: "app_close")
        var sentEvents: [String] = []
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { name, _ in
                sentEvents.append(name)
                if name == "session_start" { }
            },
            criticalEventSender: { name, _, completion in
                sentEvents.append(name)
                if name == "session_end" { appCloseExp.fulfill() }
                completion(true)
            }
        )
        let tracker = AutoTracker(eventSender: { name, _ in
            sentEvents.append(name)
            if name == "app_close" { appCloseExp.fulfill() }
        })
        tracker.enable()
        let observer = AppLifecycleObserver(sessionManager: sessionManager, autoTracker: tracker)
        observer.subscribe()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        wait(for: [appCloseExp], timeout: 5.0)
        XCTAssertTrue(sentEvents.contains("app_close"), "sentEvents: \(sentEvents)")
        _ = observer
    }

    /**
     Проверяет отправку session_end и app_close при willTerminate.
     */
    func test_willTerminate_sendsSessionEndAndAppClose() {
        let terminateExp = expectation(description: "terminate events")
        terminateExp.expectedFulfillmentCount = 2

        var sentEvents: [String] = []
        let sessionManager = SessionManager(
            sessionTimeoutMs: 60_000,
            storage: storage,
            eventSender: { name, _ in
                sentEvents.append(name)
            },
            criticalEventSender: { name, _, completion in
                sentEvents.append(name)
                if name == "session_end" { terminateExp.fulfill() }
                completion(true)
            }
        )
        let tracker = AutoTracker(eventSender: { name, _ in
            sentEvents.append(name)
            if name == "app_close" { terminateExp.fulfill() }
        })
        tracker.enable()

        let observer = AppLifecycleObserver(sessionManager: sessionManager, autoTracker: tracker)
        observer.subscribe()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        sentEvents.removeAll()
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)

        wait(for: [terminateExp], timeout: 2.0)
        XCTAssertTrue(sentEvents.contains("session_end"), "sentEvents: \(sentEvents)")
        XCTAssertTrue(sentEvents.contains("app_close"), "sentEvents: \(sentEvents)")
        XCTAssertFalse(sentEvents.contains("session_start"), "Terminate must not start a new session; sentEvents: \(sentEvents)")
        _ = observer
    }
}