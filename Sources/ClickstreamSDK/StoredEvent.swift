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
}