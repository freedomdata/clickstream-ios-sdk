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
        case drop
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
       - maxRetries: Максимальное количество повторных попыток.
     - Returns: Решение по дальнейшей обработке события.
     */
    static func evaluate(
        sendResult: EventApiClient.QueueSendResult,
        currentAttempts: Int,
        maxRetries: Int
    ) -> Decision {
        let nextAttempts = currentAttempts + 1

        switch sendResult {
        case .success, .nonRetryableFailure:
            return Decision(action: .remove, nextAttempts: nextAttempts, delaySeconds: nil)
        case .retryableFailure:
            if nextAttempts >= maxRetries {
                return Decision(action: .drop, nextAttempts: nextAttempts, delaySeconds: nil)
            }
            return Decision(
                action: .retry,
                nextAttempts: nextAttempts,
                delaySeconds: RetryPolicy.backoffDelaySeconds(attemptIndex: currentAttempts)
            )
        }
    }
}