import XCTest
@testable import ClickstreamSDK

/**
 Проверяет хранение параметров конфигурации Clickstream SDK.
 */
final class ClickstreamConfigTests: XCTestCase {

    /**
     Проверяет сохранение API-ключа и базового URL.
     */
    func test_init_storesApiKeyAndBaseUrl() {
        let config = ClickstreamConfig(apiKey: "key1", baseUrl: "https://api.example.com")
        XCTAssertEqual(config.apiKey, "key1")
        XCTAssertEqual(config.baseUrl, "https://api.example.com")
    }

    /**
     Проверяет значение таймаута сессии по умолчанию.
     */
    func test_init_defaultSessionTimeout() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u")
        XCTAssertEqual(config.sessionTimeoutMs, 5 * 60 * 1000)
    }

    /**
     Проверяет пользовательское значение таймаута сессии.
     */
    func test_init_customSessionTimeout() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u", sessionTimeoutMs: 10_000)
        XCTAssertEqual(config.sessionTimeoutMs, 10_000)
    }

    /**
     Проверяет значение автотрекинга по умолчанию.
     */
    func test_init_defaultAutoTrackingEnabled() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u")
        XCTAssertTrue(config.autoTrackingEnabled)
    }

    /**
     Проверяет пользовательское значение автотрекинга.
     */
    func test_init_customAutoTrackingEnabled() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u", autoTrackingEnabled: false)
        XCTAssertFalse(config.autoTrackingEnabled)
    }

    /**
     Проверяет пустые настройки трекинга по умолчанию.
     */
    func test_init_defaultTrackingOptions_empty() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u")
        XCTAssertTrue(config.trackingOptions.disabledFields.isEmpty)
    }

    /**
     Проверяет пользовательские настройки трекинга.
     */
    func test_init_customTrackingOptions() {
        let options = TrackingOptions(disabledFields: [.deviceId])
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u", trackingOptions: options)
        XCTAssertTrue(config.trackingOptions.disabledFields.contains(.deviceId))
    }

    /**
     Проверяет версию SDK по умолчанию.
     */
    func test_init_defaultSdkVersion() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u")
        XCTAssertEqual(config.sdkVersion, "0.0.0")
    }

    /**
     Проверяет пользовательскую версию SDK.
     */
    func test_init_customSdkVersion() {
        let config = ClickstreamConfig(apiKey: "k", baseUrl: "https://u", sdkVersion: "1.2.3")
        XCTAssertEqual(config.sdkVersion, "1.2.3")
    }
}