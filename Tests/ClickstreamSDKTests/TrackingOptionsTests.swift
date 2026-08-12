import XCTest
@testable import ClickstreamSDK

/**
 Проверяет настройки сбора стандартных параметров.
 */
final class TrackingOptionsTests: XCTestCase {

    /**
     Проверяет пустой набор отключенных параметров по умолчанию.
     */
    func test_init_empty_disabledFields() {
        let options = TrackingOptions()
        XCTAssertTrue(options.disabledFields.isEmpty)
    }

    /**
     Проверяет сохранение переданного набора отключенных параметров.
     */
    func test_init_withDisabledFields() {
        let options = TrackingOptions(disabledFields: [.deviceId, .eventName])
        XCTAssertEqual(options.disabledFields.count, 2)
        XCTAssertTrue(options.disabledFields.contains(.deviceId))
        XCTAssertTrue(options.disabledFields.contains(.eventName))
    }

    /**
     Проверяет включенное состояние параметра, которого нет в disabledFields.
     */
    func test_isEnabled_whenParamNotDisabled_returnsTrue() {
        let options = TrackingOptions(disabledFields: [.sessionId])
        XCTAssertTrue(options.isEnabled(.deviceId))
        XCTAssertTrue(options.isEnabled(.eventName))
        XCTAssertTrue(options.isEnabled(.eventDate))
    }

    /**
     Проверяет отключенное состояние параметра из disabledFields.
     */
    func test_isEnabled_whenParamDisabled_returnsFalse() {
        let options = TrackingOptions(disabledFields: [.deviceId, .eventName])
        XCTAssertFalse(options.isEnabled(.deviceId))
        XCTAssertFalse(options.isEnabled(.eventName))
        XCTAssertTrue(options.isEnabled(.sessionId))
    }

    /**
     Проверяет включенное состояние всех параметров при пустом disabledFields.
     */
    func test_isEnabled_emptyDisabled_allTrue() {
        let options = TrackingOptions()
        for param in StandardParam.allCases {
            XCTAssertTrue(options.isEnabled(param), "\(param) should be enabled")
        }
    }
}