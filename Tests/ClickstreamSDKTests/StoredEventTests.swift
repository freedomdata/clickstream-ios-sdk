import Foundation
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет хранение данных offline-события.
 */
final class StoredEventTests: XCTestCase {

    /**
     Проверяет сохранение всех полей StoredEvent.
     */
    func testInitStoresAllFields() throws {
        let payload = try XCTUnwrap(
            try? JSONSerialization.data(withJSONObject: ["eventName": "purchase"])
        )
        let event = StoredEvent(uuid: "test-uuid", payloadData: payload, attempts: 4)

        XCTAssertEqual(event.uuid, "test-uuid")
        XCTAssertEqual(event.payloadData, payload)
        XCTAssertEqual(event.attempts, 4)
    }
}