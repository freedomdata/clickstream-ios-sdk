import XCTest
@testable import ClickstreamSDK

/**
 Проверяет форматирование даты и смещения таймзоны.
 */
final class TimeUtilsTests: XCTestCase {

    /**
     Проверяет формат строки смещения таймзоны.
     */
    func test_tzOffsetString_format() {
        let tz = TimeZone(identifier: "Europe/Moscow")!
        let date = Date()
        let offset = TimeUtils.tzOffsetString(for: tz, at: date)
        XCTAssertTrue(offset.hasPrefix("+") || offset.hasPrefix("-"))
        XCTAssertEqual(offset.count, 6)
        XCTAssertTrue(offset.contains(":"))
    }

    /**
     Проверяет наличие ISO-паттерна в текущей дате.
     */
    func test_nowWithOffset_containsISOPattern() {
        let result = TimeUtils.nowWithOffset()
        XCTAssertTrue(result.contains("T"))
        XCTAssertTrue(result.contains(":") && result.contains("."))
    }
}