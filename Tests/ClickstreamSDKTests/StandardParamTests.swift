import XCTest
@testable import ClickstreamSDK

/**
 Проверяет стандартные параметры SDK.
 */
final class StandardParamTests: XCTestCase {

    /**
     Проверяет rawValue стандартных параметров.
     */
    func test_rawValues() {
        XCTAssertEqual(StandardParam.deviceId.rawValue, "deviceId")
        XCTAssertEqual(StandardParam.eventName.rawValue, "eventName")
        XCTAssertEqual(StandardParam.eventDate.rawValue, "eventDate")
        XCTAssertEqual(StandardParam.sessionId.rawValue, "sessionId")
        XCTAssertEqual(StandardParam.userId.rawValue, "userId")
        XCTAssertEqual(StandardParam.deviceContext.rawValue, "deviceContext")
        XCTAssertEqual(StandardParam.appVersion.rawValue, "appVersion")
        XCTAssertEqual(StandardParam.networkType.rawValue, "networkType")
    }

    /**
     Проверяет наличие элементов в allCases.
     */
    func test_allCases_nonEmpty() {
        XCTAssertFalse(StandardParam.allCases.isEmpty)
        XCTAssertTrue(StandardParam.allCases.contains(.deviceId))
        XCTAssertTrue(StandardParam.allCases.contains(.deviceContext))
    }

    /**
     Проверяет работу StandardParam в Set.
     */
    func test_hashable_setContains() {
        let set: Set<StandardParam> = [.deviceId, .eventName]
        XCTAssertTrue(set.contains(.deviceId))
        XCTAssertFalse(set.contains(.sessionId))
    }
}