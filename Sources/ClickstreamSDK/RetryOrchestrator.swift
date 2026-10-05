import Foundation

/**
 Определяет стратегию обработки события после попытки отправки.
 */
internal enum RetryOrchestrator {

    /**
     Описывает действие для события после попытки отправки.
     */
    enum Action {
        case remove
        case retry
    }

    /**
     Хранит решение по дальнейшей обработке события.
     */
    struct Decision {
        /**
         Действие для события после попытки отправки.
         */
        let action: Action

        /**
         Следующее количество попыток отправки события.
         */
        let nextAttempts: Int

        /**
         Задержка перед следующей попыткой отправки.
         */
        let delaySeconds: TimeInterval?
    }

    /**
     Возвращает решение по событию на основе результата отправки.
     - Parameters:
       - sendResult: Результат отправки события.
       - currentAttempts: Текущее количество попыток отправки.
       - maxRetries: Номер попытки, после которого экспоненциальная часть backoff перестает расти.
     - Returns: Решение по дальнейшей обработке события.
     */
    static func evaluate(
        sendResult: QueueSendResult,
        currentAttempts: Int,
        maxRetries: Int
    ) -> Decision {
        let nextAttempts = currentAttempts == Int.max ? Int.max : currentAttempts + 1

        switch sendResult {
        case .success, .nonRetryableFailure:
            return Decision(action: .remove, nextAttempts: nextAttempts, delaySeconds: nil)
        case .retryableFailure:
            return Decision(
                action: .retry,
                nextAttempts: nextAttempts,
                delaySeconds: RetryPolicy.backoffDelaySeconds(
                    attemptIndex: min(nextAttempts, max(1, maxRetries))
                )
            )
        }
    }
}
