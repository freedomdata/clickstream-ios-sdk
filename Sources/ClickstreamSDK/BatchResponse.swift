import Foundation

/**
 Хранит результат batch-отправки и исходный набор событий.
 */
internal struct BatchResponse: Sendable {
    let result: BatchSendResult
    let events: [StoredEvent]
}
