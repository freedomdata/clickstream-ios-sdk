import XCTest
@testable import ClickstreamSDK

/**
 Проверяет автоматическую отправку стандартных событий.
 */
final class AutoTrackerTests: XCTestCase {

    private var sentEvents: [(String, [String: Any])]!

    /**
     Подготавливает список отправленных событий перед каждым тестом.
     */
    override func setUp() {
        super.setUp()
        sentEvents = []
    }

    /**
     Создает AutoTracker с тестовым обработчиком событий.
     - Returns: Экземпляр AutoTracker для теста.
     */
    private func makeTracker() -> AutoTracker {
        AutoTracker(eventSender: { name, payload in
            self.sentEvents.append((name, payload))
        })
    }

    /**
     Проверяет включение автотрекера.
     */
    func test_enable_isEnabledReturnsTrue() {
        let tracker = makeTracker()
        tracker.enable()
        XCTAssertTrue(tracker.isEnabled())
    }

    /**
     Проверяет отключение автотрекера.
     */
    func test_disable_isEnabledReturnsFalse() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.disable()
        XCTAssertFalse(tracker.isEnabled())
    }

    /**
     Проверяет начальное отключенное состояние автотрекера.
     */
    func test_isEnabled_beforeEnable_returnsFalse() {
        let tracker = makeTracker()
        XCTAssertFalse(tracker.isEnabled())
    }

    /**
     Проверяет отправку app_start при foreground во включенном состоянии.
     */
    func test_onAppForeground_whenEnabled_sendsAppStart() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.onAppForeground()
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents[0].0, "app_start")
    }

    /**
     Проверяет отсутствие отправки app_start при выключенном автотрекере.
     */
    func test_onAppForeground_whenDisabled_doesNotSend() {
        let tracker = makeTracker()
        tracker.onAppForeground()
        XCTAssertTrue(sentEvents.isEmpty)
    }

    /**
     Проверяет отправку app_close при background во включенном состоянии.
     */
    func test_onAppBackground_whenEnabled_sendsAppClose() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.onAppBackground()
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents[0].0, "app_close")
    }

    /**
     Проверяет отсутствие отправки app_close при выключенном автотрекере.
     */
    func test_onAppBackground_whenDisabled_doesNotSend() {
        let tracker = makeTracker()
        tracker.onAppBackground()
        XCTAssertTrue(sentEvents.isEmpty)
    }

    /**
     Проверяет отправку screen_view при показе экрана во включенном состоянии.
     */
    func test_onScreenResumed_whenEnabled_sendsScreenView() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.onScreenResumed(screenName: "TestScreen")
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents[0].0, "screen_view")
        XCTAssertEqual(sentEvents[0].1["screen"] as? String, "TestScreen")
    }

    /**
     Проверяет отсутствие отправки screen_view при выключенном автотрекере.
     */
    func test_onScreenResumed_whenDisabled_doesNotSend() {
        let tracker = makeTracker()
        tracker.onScreenResumed(screenName: "TestScreen")
        XCTAssertTrue(sentEvents.isEmpty)
    }

    /**
     Проверяет добавление previousScreen при переходе между разными экранами.
     */
    func test_onScreenResumed_differentScreens_includesPreviousScreen() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.onScreenResumed(screenName: "ScreenA")
        tracker.onScreenResumed(screenName: "ScreenB")
        XCTAssertEqual(sentEvents.count, 2)
        XCTAssertEqual(sentEvents[1].1["screen"] as? String, "ScreenB")
        XCTAssertEqual(sentEvents[1].1["previousScreen"] as? String, "ScreenA")
    }

    /**
     Проверяет отправку deeplink_open во включенном состоянии.
     */
    func test_reportDeeplinkOpen_whenEnabled_sendsDeeplinkOpen() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.reportDeeplinkOpen(url: "demo://path")
        XCTAssertEqual(sentEvents.count, 1)
        XCTAssertEqual(sentEvents[0].0, "deeplink_open")
        XCTAssertEqual(sentEvents[0].1["deeplink"] as? String, "demo://path")
    }

    /**
     Проверяет отсутствие отправки deeplink_open при выключенном автотрекере.
     */
    func test_reportDeeplinkOpen_whenDisabled_doesNotSend() {
        let tracker = makeTracker()
        tracker.reportDeeplinkOpen(url: "demo://path")
        XCTAssertTrue(sentEvents.isEmpty)
    }

    /**
     Проверяет повторную отправку deeplink_open для одинакового URL.
     */
    func test_reportDeeplinkOpen_sameUrlTwice_sendsTwice() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.reportDeeplinkOpen(url: "demo://same")
        tracker.reportDeeplinkOpen(url: "demo://same")
        XCTAssertEqual(sentEvents.count, 2)
        XCTAssertEqual(sentEvents[0].1["deeplink"] as? String, "demo://same")
        XCTAssertEqual(sentEvents[1].1["deeplink"] as? String, "demo://same")
    }

    /**
     Проверяет отправку deeplink_open для разных URL.
     */
    func test_reportDeeplinkOpen_differentUrls_sendsBoth() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.reportDeeplinkOpen(url: "demo://a")
        tracker.reportDeeplinkOpen(url: "demo://b")
        XCTAssertEqual(sentEvents.count, 2)
        XCTAssertEqual(sentEvents[0].1["deeplink"] as? String, "demo://a")
        XCTAssertEqual(sentEvents[1].1["deeplink"] as? String, "demo://b")
    }

    /**
     Проверяет идемпотентность повторного включения автотрекера.
     */
    func test_enable_twice_idempotent() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.enable()
        XCTAssertTrue(tracker.isEnabled())
        tracker.onAppForeground()
        XCTAssertEqual(sentEvents.count, 1)
    }

    /**
     Проверяет безопасное повторное отключение автотрекера.
     */
    func test_disable_whenAlreadyDisabled_doesNotCrash() {
        let tracker = makeTracker()
        tracker.disable()
        tracker.disable()
        XCTAssertFalse(tracker.isEnabled())
    }

    /**
     Проверяет фильтрацию повторного screen_view в пределах throttle.
     */
    func test_onScreenResumed_sameScreenWithinThrottle_sendsOnce() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.onScreenResumed(screenName: "ScreenA")
        tracker.onScreenResumed(screenName: "ScreenA")
        XCTAssertEqual(sentEvents.count, 1)
    }

    /**
     Проверяет фильтрацию одинаковых логических имен экранов.
     */
    func test_onScreenResumed_sameLogicalScreenName_filtered() {
        let tracker = makeTracker()
        tracker.enable()
        tracker.onScreenResumed(screenName: "HomeViewController")
        tracker.onScreenResumed(screenName: "HomeView")
        XCTAssertEqual(sentEvents.count, 1)
    }
}