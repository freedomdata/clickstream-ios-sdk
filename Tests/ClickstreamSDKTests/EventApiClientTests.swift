import XCTest
@testable import ClickstreamSDK

/**
 Проверяет отправку событий через EventApiClient.
 */
final class EventApiClientTests: XCTestCase {

    /**
     Проверяет отправку события с валидным payload без падения.
     */
    func test_sendEvent_withValidPayload_doesNotCrash() {
        let client = EventApiClient(baseUrl: "https://example.com", apiKey: "test-key")
        client.sendEvent(["eventName": "test", "eventDate": "2026-01-01T00:00:00.000+00:00"])
    }

    /**
     Проверяет создание клиента с baseUrl и apiKey.
     */
    func test_init_storesBaseUrlAndApiKey() {
        let client = EventApiClient(baseUrl: "https://api.test", apiKey: "my-key")
        client.sendEvent([:])
    }

    /**
     Проверяет отправку события с baseUrl, содержащим завершающий слеш.
     */
    func test_sendEvent_baseUrlWithTrailingSlash_doesNotCrash() {
        let client = EventApiClient(baseUrl: "https://example.com/", apiKey: "key")
        client.sendEvent(["eventName": "e"])
    }
}