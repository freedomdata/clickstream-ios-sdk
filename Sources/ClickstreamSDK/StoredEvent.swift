import Foundation

/**
 Хранит offline-событие для очереди отправки.
 */
internal struct StoredEvent: Sendable {
    /**
     Уникальный идентификатор события.
     */
    let uuid: String

    /**
     JSON-данные события.
     */
    let payloadData: Data

    /**
     Количество неудачных попыток отправки.
     */
    let attempts: Int

    /**
     Устойчивый порядок добавления события в очередь.
     */
    let sequence: Int64?

    /**
     Создает сохраненное событие с метаданными очереди.
     - Parameters:
       - uuid: Уникальный идентификатор события.
       - payloadData: JSON-данные события.
       - attempts: Количество неудачных попыток отправки.
       - sequence: Устойчивый порядковый номер события.
     */
    init(uuid: String, payloadData: Data, attempts: Int, sequence: Int64? = nil) {
        self.uuid = uuid
        self.payloadData = payloadData
        self.attempts = attempts
        self.sequence = sequence
    }
}
