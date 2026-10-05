import Foundation

/**
 Описывает результат legacy-отправки события для очереди.
 */
internal enum QueueSendResult: Sendable {
    case success
    case retryableFailure
    case nonRetryableFailure
}
