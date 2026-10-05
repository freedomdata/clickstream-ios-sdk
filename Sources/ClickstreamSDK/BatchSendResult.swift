import Foundation

/**
 Описывает результат отправки batch-запроса.
 */
internal enum BatchSendResult: Sendable {
    case processed(results: [BatchEventResult])
    case retryableFailure(retryAfterSeconds: TimeInterval?)
    case nonRetryableHTTPFailure(statusCode: Int)
    case nonRetryableTransportFailure
}
