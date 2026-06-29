import XCTest
@testable import ClickstreamSDK

/**
 Проверяет сборку endpoint URL из baseUrl конфигурации.
 */
final class ClickstreamURLBuilderTests: XCTestCase {

    /**
     Проверяет URL отправки событий для baseUrl без path.
     */
    func test_eventEndpointURL_withoutPath_usesSameHostAndPlatformPath() {
        let url = ClickstreamURLBuilder.eventEndpointURL(baseUrl: "https://gateway.example.com")

        XCTAssertEqual(
            url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest/event"
        )
    }

    /**
     Проверяет legacy URL отправки событий для baseUrl с path event-сервиса.
     */
    func test_eventEndpointURL_withEventServicePath_appendsEventSuffix() {
        let url = ClickstreamURLBuilder.eventEndpointURL(
            baseUrl: "https://gateway.example.com/api/click-stream-rest"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest/event"
        )
    }

    /**
     Проверяет legacy URL отправки событий для произвольного path в baseUrl.
     */
    func test_eventEndpointURL_withCustomPath_appendsEventSuffix() {
        let url = ClickstreamURLBuilder.eventEndpointURL(
            baseUrl: "https://gateway.example.com/custom/event-service"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://gateway.example.com/custom/event-service/event"
        )
    }

    /**
     Проверяет нормализацию baseUrl с завершающим слешом для event endpoint.
     */
    func test_eventEndpointURL_withTrailingSlash_normalizesBaseUrl() {
        let url = ClickstreamURLBuilder.eventEndpointURL(baseUrl: "https://gateway.example.com/")

        XCTAssertEqual(
            url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest/event"
        )
    }

    /**
     Проверяет URL флагов на том же host при baseUrl без path.
     */
    func test_flagsEndpointURL_withoutPath_usesSameHostAndPlatformPath() {
        let url = ClickstreamURLBuilder.flagsEndpointURL(
            baseUrl: "https://gateway.example.com",
            deviceId: "device-1"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest-flag/flag/device-1"
        )
    }

    /**
     Проверяет, что path в baseUrl игнорируется для flags endpoint.
     */
    func test_flagsEndpointURL_withPathInBaseUrl_usesSameHostAndPlatformPath() {
        let url = ClickstreamURLBuilder.flagsEndpointURL(
            baseUrl: "https://gateway.example.com/api/click-stream-rest",
            deviceId: "device-1"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest-flag/flag/device-1"
        )
    }
}
