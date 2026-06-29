import XCTest
@testable import ClickstreamSDK

/**
 Проверяет объединение пользовательских свойств с параметрами SDK.
 */
final class UserPropertiesContextMergerTests: XCTestCase {

    /**
     Проверяет приоритет пользовательских значений над параметрами SDK.
     */
    func test_merge_preservesCustomOverSdk() {
        let custom: [String: Any] = ["appVersion": "9.9.9", "tier": "gold"]
        let sdk: [String: Any?] = [
            "appVersion": "1.0.0",
            "locale": "en_US",
            "sdkVersion": "2.0.0",
        ]
        let merged = UserPropertiesContextMerger.merge(custom: custom, sdkParams: sdk)
        XCTAssertEqual(merged["appVersion"] as? String, "9.9.9")
        XCTAssertEqual(merged["locale"] as? String, "en_US")
        XCTAssertEqual(merged["sdkVersion"] as? String, "2.0.0")
        XCTAssertEqual(merged["tier"] as? String, "gold")
    }

    /**
     Проверяет замену nil-значений SDK на NSNull.
     */
    func test_merge_sdkNil_becomesNSNull() {
        let custom: [String: Any] = [:]
        let sdk: [String: Any?] = ["carrier": nil]
        let merged = UserPropertiesContextMerger.merge(custom: custom, sdkParams: sdk)
        XCTAssertTrue(merged["carrier"] is NSNull)
    }
}