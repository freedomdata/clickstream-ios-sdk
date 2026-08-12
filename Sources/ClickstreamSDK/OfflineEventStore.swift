import Foundation

/**
 Хранит offline-события на диске.
 */
internal final class OfflineEventStore {

    private static let indexFileName = "queue_index.json"

    private let maxEvents: Int
    private let fileManager: FileManager
    private let eventsDirectory: URL

    private var queue: [String] = []

    /**
     Создает хранилище offline-событий и восстанавливает очередь с диска.
     - Parameters:
       - maxEvents: Максимальное количество событий в хранилище.
       - fileManager: Файловый менеджер для работы с диском.
     */
    init(maxEvents: Int, fileManager: FileManager = .default) {
        self.maxEvents = maxEvents
        self.fileManager = fileManager
        self.eventsDirectory = Self.makeEventsDirectory(fileManager: fileManager)
        self.queue = Self.restoreQueue(fileManager: fileManager, eventsDirectory: eventsDirectory, maxEvents: maxEvents)
    }

    /**
     Возвращает URL файла индекса очереди.
     */
    private var queueIndexUrl: URL {
        eventsDirectory.appendingPathComponent(Self.indexFileName)
    }

    /**
     Возвращает URL файла события по его UUID.
     - Parameters:
       - uuid: Уникальный идентификатор события.
     - Returns: URL файла события.
     */
    private func eventUrl(uuid: String) -> URL {
        eventsDirectory.appendingPathComponent("\(uuid).json")
    }

    /**
     Добавляет событие в хранилище и возвращает новый размер очереди.
     - Parameters:
       - payload: Данные события для сохранения.
     - Returns: Текущий размер очереди.
     */
    func add(payload: [String: Any]) -> Int {
        let uuid = UUID().uuidString
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return queue.count
        }
        let event = StoredEvent(uuid: uuid, payloadData: payloadData, attempts: 0)
        guard let data = serialize(event) else { return queue.count }
        do {
            try data.write(to: eventUrl(uuid: uuid), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            queue.append(uuid)
            trimIfNeeded()
            persistIndex()
            return queue.count
        } catch {
            ClickstreamLogger.log("OfflineEventStore: failed to write event: \(error)")
            return queue.count
        }
    }

    /**
     Возвращает количество событий в очереди.
     */
    var count: Int { queue.count }

    /**
     Проверяет, пуста ли очередь событий.
     */
    var isEmpty: Bool { queue.isEmpty }

    /**
     Возвращает первое событие из очереди без удаления.
     - Returns: Первое событие очереди или nil.
     */
    func peek() -> StoredEvent? {
        while let uuid = queue.first {
            guard let data = try? Data(contentsOf: eventUrl(uuid: uuid)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stored = parseStoredEvent(uuid: uuid, json: json, rawData: data) else {
                queue.removeAll { $0 == uuid }
                try? fileManager.removeItem(at: eventUrl(uuid: uuid))
                persistIndex()
                continue
            }
            return stored
        }
        return nil
    }

    /**
     Удаляет первое событие из очереди и с диска.
     */
    func removeFirst() {
        guard !queue.isEmpty else { return }
        let uuid = queue.removeFirst()
        try? fileManager.removeItem(at: eventUrl(uuid: uuid))
        persistIndex()
    }

    /**
     Обновляет количество попыток отправки события.
     - Parameters:
       - uuid: Уникальный идентификатор события.
       - newAttempts: Новое количество попыток отправки.
     */
    func updateAttempts(uuid: String, newAttempts: Int) {
        guard let idx = queue.firstIndex(of: uuid) else { return }
        let url = eventUrl(uuid: uuid)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var stored = parseStoredEvent(uuid: uuid, json: json, rawData: data) else {
            queue.remove(at: idx)
            try? fileManager.removeItem(at: url)
            persistIndex()
            return
        }
        stored = StoredEvent(uuid: uuid, payloadData: stored.payloadData, attempts: newAttempts)
        if let out = serialize(stored) {
            try? out.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /**
     Сериализует сохраненное событие в JSON.
     - Parameters:
       - event: Событие для сериализации.
     - Returns: Данные JSON или nil.
     */
    private func serialize(_ event: StoredEvent) -> Data? {
        guard let payloadObj = try? JSONSerialization.jsonObject(with: event.payloadData) else { return nil }
        let dict: [String: Any] = [
            "uuid": event.uuid,
            "payload": payloadObj,
            "attempts": event.attempts
        ]
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    /**
     Преобразует JSON события в модель StoredEvent.
     - Parameters:
       - uuid: Уникальный идентификатор события.
       - json: JSON-словарь сохраненного события.
       - rawData: Исходные данные события.
     - Returns: Сохраненное событие или nil.
     */
    private func parseStoredEvent(uuid: String, json: [String: Any], rawData: Data) -> StoredEvent? {
        if let payload = json["payload"] as? [String: Any],
           let payloadData = try? JSONSerialization.data(withJSONObject: payload) {
            let attempts = (json["attempts"] as? Int) ?? 0
            return StoredEvent(uuid: uuid, payloadData: payloadData, attempts: attempts)
        }
        if json["uuid"] == nil, json["attempts"] == nil,
           let payloadData = try? JSONSerialization.data(withJSONObject: json) {
            return StoredEvent(uuid: uuid, payloadData: payloadData, attempts: 0)
        }
        let attempts = (json["attempts"] as? Int) ?? 0
        return StoredEvent(uuid: uuid, payloadData: rawData, attempts: attempts)
    }

    /**
     Удаляет старые события при превышении максимального размера очереди.
     */
    private func trimIfNeeded() {
        while queue.count > maxEvents, let uuid = queue.first {
            queue.removeFirst()
            try? fileManager.removeItem(at: eventUrl(uuid: uuid))
        }
        persistIndex()
    }

    /**
     Сохраняет индекс очереди на диск.
     */
    private func persistIndex() {
        guard let data = try? JSONSerialization.data(withJSONObject: queue) else { return }
        try? data.write(to: queueIndexUrl, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /**
     Создает и возвращает каталог для файлов событий.
     - Parameters:
       - fileManager: Файловый менеджер для создания каталога.
     - Returns: URL каталога событий.
     */
    private static func makeEventsDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("com.clickstream.sdk/events", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dir.path
        )
        var mutableDir = dir
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }

    /**
     Восстанавливает очередь событий с диска.
     - Parameters:
       - fileManager: Файловый менеджер для чтения файлов.
       - eventsDirectory: Каталог файлов событий.
       - maxEvents: Максимальное количество событий в очереди.
     - Returns: Массив UUID восстановленных событий.
     */
    private static func restoreQueue(fileManager: FileManager, eventsDirectory: URL, maxEvents: Int) -> [String] {
        let indexUrl = eventsDirectory.appendingPathComponent(indexFileName)
        if let data = try? Data(contentsOf: indexUrl),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            var result: [String] = []
            for uuid in arr {
                let path = eventsDirectory.appendingPathComponent("\(uuid).json").path
                if fileManager.fileExists(atPath: path) {
                    result.append(uuid)
                }
            }
            while result.count > maxEvents, let first = result.first {
                result.removeFirst()
                try? fileManager.removeItem(atPath: eventsDirectory.appendingPathComponent("\(first).json").path)
            }
            if let indexData = try? JSONSerialization.data(withJSONObject: result) {
                try? indexData.write(to: indexUrl, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return result
        }

        guard let files = try? fileManager.contentsOfDirectory(at: eventsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        let names = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != indexFileName }
            .map(\.lastPathComponent)
            .sorted()
        var uuids: [String] = []
        for name in names {
            let id = (name as NSString).deletingPathExtension
            if !id.isEmpty { uuids.append(id) }
        }
        while uuids.count > maxEvents, let first = uuids.first {
            uuids.removeFirst()
            try? fileManager.removeItem(atPath: eventsDirectory.appendingPathComponent("\(first).json").path)
        }
        if let indexData = try? JSONSerialization.data(withJSONObject: uuids) {
            try? indexData.write(to: indexUrl, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return uuids
    }
}