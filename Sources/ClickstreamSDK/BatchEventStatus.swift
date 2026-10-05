import Foundation

/**
 Описывает статус обработки одного события в batch-ответе.
 */
internal enum BatchEventStatus: String, Sendable, Equatable {
    case success = "SUCCESS"
    case failed = "FAILED"
    case skipped = "SKIPPED"
}
