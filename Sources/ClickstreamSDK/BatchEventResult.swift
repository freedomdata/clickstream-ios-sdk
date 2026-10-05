import Foundation

/**
 Хранит результат обработки события с его позицией в batch.
 */
internal struct BatchEventResult: Sendable {
    let index: Int
    let status: BatchEventStatus
    let message: String?
}
