import XCTest
@testable import ClickstreamSDK

/**
 Проверяет безопасный вывод логов Clickstream SDK.
 */
final class ClickstreamLoggerTests: XCTestCase {

    /**
     Проверяет вывод обычного сообщения без падения.
     */
    func test_log_doesNotCrash() {
        ClickstreamLogger.log("test message")
    }

    /**
     Проверяет вывод пустого сообщения без падения.
     */
    func test_log_emptyString_doesNotCrash() {
        ClickstreamLogger.log("")
    }

    /**
     Проверяет вывод сообщения со специальными символами без падения.
     */
    func test_log_specialCharacters_doesNotCrash() {
        ClickstreamLogger.log("emoji: \u{1F600} \n\t")
    }
}