import Foundation

/**
 Ограничивает выполнение completion сетевого запроса события одним вызовом.
 */
internal final class EventApiCompletionGate: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var claimed = false

    /**
     Проверяет и фиксирует первый вызов completion.
     - Returns: Флаг успешной фиксации первого вызова.
     */
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
