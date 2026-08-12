import XCTest
@testable import ClickstreamSDK

/**
 Проверяет выбор стратегии повторной отправки событий.
 */
final class RetryOrchestratorTests: XCTestCase {

    /**
     Проверяет решение remove при успешной отправке.
     */
    func testEvaluateSuccessReturnsRemoveDecision() {
        let decision = RetryOrchestrator.evaluate(
            sendResult: .success,
            currentAttempts: 1,
            maxRetries: 5
        )

        XCTAssertEqual(decision.action, .remove)
        XCTAssertEqual(decision.nextAttempts, 2)
        XCTAssertNil(decision.delaySeconds)
    }

    /**
     Проверяет решение remove при non-retryable ошибке.
     */
    func testEvaluateNonRetryableFailureReturnsRemoveDecision() {
        let decision = RetryOrchestrator.evaluate(
            sendResult: .nonRetryableFailure,
            currentAttempts: 0,
            maxRetries: 5
        )

        XCTAssertEqual(decision.action, .remove)
        XCTAssertEqual(decision.nextAttempts, 1)
        XCTAssertNil(decision.delaySeconds)
    }

    /**
     Проверяет решение retry с задержкой при retryable ошибке ниже лимита.
     */
    func testEvaluateRetryableFailureBelowMaxReturnsRetryDecisionWithDelay() {
        let decision = RetryOrchestrator.evaluate(
            sendResult: .retryableFailure,
            currentAttempts: 2,
            maxRetries: 5
        )

        XCTAssertEqual(decision.action, .retry)
        XCTAssertEqual(decision.nextAttempts, 3)
        XCTAssertNotNil(decision.delaySeconds)
        if let delay = decision.delaySeconds {
            XCTAssertGreaterThanOrEqual(delay, 4.0)
            XCTAssertLessThanOrEqual(delay, 5.0)
        }
    }

    /**
     Проверяет решение drop при исчерпании лимита повторных попыток.
     */
    func testEvaluateRetryableFailureAtMaxReturnsDropDecision() {
        let decision = RetryOrchestrator.evaluate(
            sendResult: .retryableFailure,
            currentAttempts: 2,
            maxRetries: 3
        )

        XCTAssertEqual(decision.action, .drop)
        XCTAssertEqual(decision.nextAttempts, 3)
        XCTAssertNil(decision.delaySeconds)
    }
}