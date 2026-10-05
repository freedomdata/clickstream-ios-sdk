import Foundation

/**
 Вычисляет задержку перед повторной попыткой отправки события.
 */
internal enum RetryPolicy {

    private static let maxDelaySeconds: TimeInterval = 30.0
    private static let maxJitterSeconds: TimeInterval = 1.0

    /**
     Возвращает задержку перед повторной попыткой отправки.
     - Parameters:
       - attemptIndex: Индекс текущей попытки отправки.
     - Returns: Задержка перед повторной попыткой в секундах.
     */
    static func backoffDelaySeconds(attemptIndex: Int) -> TimeInterval {
        let normalizedAttemptIndex = max(0, attemptIndex)
        let exponentialDelay = min(pow(2.0, Double(normalizedAttemptIndex)), maxDelaySeconds)
        let jitter = Double.random(in: 0...maxJitterSeconds)
        return exponentialDelay + jitter
    }
}