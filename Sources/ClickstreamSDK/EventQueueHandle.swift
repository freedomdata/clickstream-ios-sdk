@preconcurrency import Dispatch
import Foundation

/**
 Передает результат отправки обратно на serial queue EventQueue.
 */
internal final class EventQueueHandle: Sendable {
    nonisolated(unsafe) private weak var queue: EventQueue?

    /**
     Создает weak-обертку над очередью событий.
     - Parameter queue: Очередь, принимающая результат batch-запроса.
     */
    init(_ queue: EventQueue) {
        self.queue = queue
    }

    /**
     Доставляет результат отправки на serial queue EventQueue.
     - Parameters:
       - response: Результат batch-запроса с исходными событиями.
       - ioQueue: Serial queue для обработки результата.
     */
    func deliver(_ response: BatchResponse, on ioQueue: DispatchQueue) {
        ioQueue.async { [self] in
            queue?.handleBatchResponse(response)
        }
    }
}
