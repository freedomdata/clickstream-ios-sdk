import UIKit
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет публичные методы ClickstreamSDK.
 */
final class ClickstreamSDKTests: XCTestCase {

    /**
     Выполняет очистку после каждого теста.
     */
    override func tearDown() {
        super.tearDown()
    }

    /**
     Проверяет отправку события без инициализации SDK.
     */
    func test_trackEvent_withoutInit_doesNotCrash() {
        ClickstreamSDK.trackEvent("test_event", props: ["a": "b"])
    }

    /**
     Проверяет старт сессии при didBecomeActive.
     */
    func test_didBecomeActive_startsSession() {
        let storage = SessionStorage()
        storage.clear()

        let expectation = expectation(description: "session_start received")
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
     Проверяет безопасное переключение автотрекинга.
     */
    func test_setAutoTrackingEnabled_doesNotCrash() {
        ClickstreamSDK.setAutoTrackingEnabled(true)
        ClickstreamSDK.setAutoTrackingEnabled(false)
    }

    /**
     Проверяет получение состояния автотрекинга.
     */
    func test_isAutoTrackingEnabled_returnsBool() {
        _ = ClickstreamSDK.isAutoTrackingEnabled()
    }

    /**
     Проверяет ручной отчет о показе экрана без падения.
     */
    func test_reportScreenView_doesNotCrash() {
        ClickstreamSDK.reportScreenView("TestScreen")
    }

    /**
     Проверяет отчет о deep link строкой без падения.
     */
    func test_reportDeeplinkOpen_string_doesNotCrash() {
        ClickstreamSDK.reportDeeplinkOpen("demo://path")
    }

    /**
     Проверяет отчет о deep link через URL без падения.
     */
    func test_reportDeeplinkOpen_url_doesNotCrash() {
        ClickstreamSDK.reportDeeplinkOpen(URL(string: "https://example.com")!)
    }

    /**
     Проверяет повторную инициализацию SDK без падения.
     */
    func test_initialize_twice_doesNotCrash() {
        let config = ClickstreamConfig(apiKey: "key", baseUrl: "https://example.com")
        ClickstreamSDK.initialize(config: config)
        ClickstreamSDK.initialize(config: config)
    }

    /**
     Проверяет установку userId без инициализации SDK.
     */
    func test_setUserId_withoutInit_doesNotCrash() {
        ClickstreamSDK.setUserId("user1")
    }

    /**
     Проверяет установку пустого userId без падения.
     */
    func test_setUserId_empty_doesNotCrash() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://example.com")
        ClickstreamSDK.initialize(config: config)
        ClickstreamSDK.setUserId("")
        ClickstreamSDK.setUserId("   ")
    }

    /**
     Проверяет очистку userId без падения.
     */
    func test_clearUserId_doesNotCrash() {
        ClickstreamSDK.clearUserId()
    }

    /**
     Проверяет установку TrackingOptions без инициализации SDK.
     */
    func test_setTrackingOptions_withoutInit_doesNotCrash() {
        ClickstreamSDK.setTrackingOptions(TrackingOptions(disabledFields: [.deviceId]))
    }

    /**
     Проверяет установку TrackingOptions после инициализации SDK.
     */
    func test_setTrackingOptions_afterInit_doesNotCrash() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://example.com")
        ClickstreamSDK.initialize(config: config)
        ClickstreamSDK.setTrackingOptions(TrackingOptions(disabledFields: [.eventDate]))
    }

    /**
     Проверяет установку пользовательских свойств без инициализации SDK.
     */
    func test_setUserProperties_withoutInit_doesNotCrash() {
        ClickstreamSDK.setUserProperties(["role": "admin"])
    }

    /**
     Проверяет установку пользовательских свойств после инициализации SDK.
     */
    func test_setUserProperties_afterInit_doesNotCrash() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://example.com")
        ClickstreamSDK.initialize(config: config)
        ClickstreamSDK.setUserProperties(["segment": "premium"])
    }

    /**
     Проверяет отправку события после инициализации SDK.
     */
    func test_trackEvent_afterInit_doesNotCrash() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://example.com")
        ClickstreamSDK.initialize(config: config)
        ClickstreamSDK.trackEvent("custom_event", props: ["key": "value"])
    }

    /**
     Проверяет отчет о показе технического и обычного экрана без падения.
     */
    func test_reportScreenView_presentationHostingControllerAndNormal_doesNotCrash() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://example.com")
        ClickstreamSDK.initialize(config: config)
        ClickstreamSDK.reportScreenView("PresentationHostingController<SomeView>")
        ClickstreamSDK.reportScreenView("NormalScreen")
    }
}