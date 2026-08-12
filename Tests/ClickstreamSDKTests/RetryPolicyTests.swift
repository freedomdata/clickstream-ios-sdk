import XCTest
@testable import ClickstreamSDK

/**
 Проверяет расчет задержки перед повторной отправкой.
 */
final class RetryPolicyTests: XCTestCase {

    /**
     Проверяет диапазон задержки для отрицательного индекса попытки.
     */
    func testBackoffDelaySecondsForNegativeAttemptUsesZeroAttemptRange() {
        let delay = RetryPolicy.backoffDelaySeconds(attemptIndex: -3)

        XCTAssertGreaterThanOrEqual(delay, 1.0)
        XCTAssertLessThanOrEqual(delay, 2.0)
    }

    /**
     Проверяет экспоненциальный диапазон задержки для третьей попытки.
     */
    func testBackoffDelaySecondsForAttemptThreeUsesExponentialRange() {
        let delay = RetryPolicy.backoffDelaySeconds(attemptIndex: 3)

        XCTAssertGreaterThanOrEqual(delay, 8.0)
        XCTAssertLessThanOrEqual(delay, 9.0)
    }

    /**
     Проверяет ограничение максимальной задержки для большого индекса попытки.
     */
    func testBackoffDelaySecondsForLargeAttemptIsCapped() {
        let delay = RetryPolicy.backoffDelaySeconds(attemptIndex: 100)

        XCTAssertGreaterThanOrEqual(delay, 30.0)
        XCTAssertLessThanOrEqual(delay, 31.0)
    }
}