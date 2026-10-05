import Foundation

/**
 Хранит offline-события на диске.
 */
internal final class OfflineEventStore {

    struct AddResult {
        let eventIdentifier: String
        let discardedEventIdentifiers: Set<String>
    }

    struct BatchResult {
        let events: [StoredEvent]
        let discardedEventIdentifiers: Set<String>
    }

    private static let indexFileName = "queue_index.json"

    private struct EventFileRecord {
        let uuid: String
        let sequence: Int64?
        let modifiedAt: Date
    }

    private struct RestoredQueue {
        let uuids: [String]
        let nextSequence: Int64
    }

    private let maxEvents: Int
    private let fileManager: FileManager
    private let eventsDirectory: URL
    private let indexWriter: (Data, URL) throws -> Void

    private var queue: [String] = []
    private var nextSequence: Int64

    /**
     Создает хранилище offline-событий и восстанавливает очередь с диска.
     - Parameters:
       - maxEvents: Максимальное количество событий в хранилище.
       - fileManager: Файловый менеджер для работы с диском.
       - indexWriter: Функция атомарной записи индекса.
     */
    init(
        maxEvents: Int,
        fileManager: FileManager = .default,
        indexWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    ) {
        self.maxEvents = maxEvents
        self.fileManager = fileManager
        self.eventsDirectory = Self.makeEventsDirectory(fileManager: fileManager)
        self.indexWriter = indexWriter
        let restored = Self.restoreQueue(fileManager: fileManager, eventsDirectory: eventsDirectory, maxEvents: maxEvents)
        self.queue = restored.uuids
        self.nextSequence = restored.nextSequence
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
        _ = addAndReport(payload: payload)
        return queue.count
    }

    /**
     Добавляет событие и сообщает, удалось ли сохранить его на диске.
     - Parameters:
       - payload: Данные события для сохранения.
     - Returns: Флаг успешной записи события.
     */
    func addAndReport(payload: [String: Any]) -> Bool {
        addAndReturnIdentifier(payload: payload) != nil
    }

    /**
     Добавляет событие и возвращает его идентификатор после успешного сохранения.
     - Parameters:
       - payload: Данные события для сохранения.
     - Returns: Идентификатор сохраненного события или nil при ошибке.
     */
    func addAndReturnIdentifier(payload: [String: Any]) -> String? {
        addAndReportDiscarded(payload: payload)?.eventIdentifier
    }

    /**
     Добавляет событие и возвращает его идентификатор вместе с вытесненными элементами очереди.
     - Parameters:
       - payload: Данные события для сохранения.
     - Returns: Результат добавления или nil при ошибке.
     */
    func addAndReportDiscarded(payload: [String: Any]) -> AddResult? {
        let uuid = UUID().uuidString
        let sequence = nextSequence
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let data = serialize(StoredEvent(uuid: uuid, payloadData: payloadData, attempts: 0, sequence: sequence)) else {
            return nil
        }
        let previousQueue = queue
        let candidateQueue = Array((queue + [uuid]).suffix(max(0, maxEvents)))
        let trimmedUUIDs = Set(queue + [uuid]).subtracting(candidateQueue)
        do {
            try data.write(to: eventUrl(uuid: uuid), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            queue = candidateQueue
            guard persistIndex() else {
                queue = previousQueue
                try? fileManager.removeItem(at: eventUrl(uuid: uuid))
                return nil
            }
            nextSequence = sequence == Int64.max ? Int64.max : sequence + 1
            for trimmedUUID in trimmedUUIDs {
                try? fileManager.removeItem(at: eventUrl(uuid: trimmedUUID))
            }
            return queue.contains(uuid)
                ? AddResult(eventIdentifier: uuid, discardedEventIdentifiers: trimmedUUIDs)
                : nil
        } catch {
            queue = previousQueue
            try? fileManager.removeItem(at: eventUrl(uuid: uuid))
            ClickstreamLogger.log("OfflineEventStore: failed to write event: \(error)")
            return nil
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
     Возвращает FIFO-подмножество событий в пределах заданного количества.
     - Parameters:
       - maxCount: Максимальное количество событий в batch.
     - Returns: Выбранные события без удаления из хранилища.
     */
    func batch(maxCount: Int) -> [StoredEvent] {
        batchAndReportDiscarded(maxCount: maxCount).events
    }

    /**
     Возвращает FIFO batch вместе с идентификаторами удаленных поврежденных событий.
     - Parameters:
       - maxCount: Максимальное количество событий в batch.
     - Returns: Выбранные и удаленные поврежденные события.
     */
    func batchAndReportDiscarded(maxCount: Int) -> BatchResult {
        let countLimit = max(1, maxCount)
        var selected: [StoredEvent] = []
        var discardedEventIdentifiers = Set<String>()
        var index = 0

        while index < queue.count, selected.count < countLimit {
            let uuid = queue[index]
            guard let event = readEvent(uuid: uuid) else {
                queue.remove(at: index)
                try? fileManager.removeItem(at: eventUrl(uuid: uuid))
                persistIndex()
                discardedEventIdentifiers.insert(uuid)
                continue
            }

            selected.append(event)
            index += 1
        }
        return BatchResult(
            events: selected,
            discardedEventIdentifiers: discardedEventIdentifiers
        )
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
     Удаляет указанные события из очереди и с диска, сохраняя порядок остальных.
     - Parameters:
       - uuids: Идентификаторы событий для удаления.
     */
    func remove(uuids: Set<String>) {
        guard !uuids.isEmpty else { return }
        let removed = queue.filter { uuids.contains($0) }
        queue.removeAll { uuids.contains($0) }
        for uuid in removed {
            try? fileManager.removeItem(at: eventUrl(uuid: uuid))
        }
        persistIndex()
    }

    /**
     Обновляет количество попыток отправки сразу для нескольких событий.
     - Parameters:
       - events: События, для которых нужно увеличить счетчик попыток.
     - Returns: Максимальное обновленное количество попыток.
     */
    func updateAttempts(for events: [StoredEvent]) -> Int {
        var maxAttempts = 0
        for event in events {
            let nextAttempts = event.attempts == Int.max ? Int.max : event.attempts + 1
            updateAttempts(uuid: event.uuid, newAttempts: nextAttempts)
            maxAttempts = max(maxAttempts, nextAttempts)
        }
        return maxAttempts
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
        stored = StoredEvent(
            uuid: uuid,
            payloadData: stored.payloadData,
            attempts: newAttempts,
            sequence: stored.sequence
        )
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
        var dict: [String: Any] = [
            "uuid": event.uuid,
            "payload": payloadObj,
            "attempts": event.attempts
        ]
        if let sequence = event.sequence {
            dict["sequence"] = sequence
        }
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
            let sequence = (json["sequence"] as? NSNumber)?.int64Value
            return StoredEvent(uuid: uuid, payloadData: payloadData, attempts: attempts, sequence: sequence)
        }
        if json["uuid"] == nil, json["attempts"] == nil,
           let payloadData = try? JSONSerialization.data(withJSONObject: json) {
            return StoredEvent(uuid: uuid, payloadData: payloadData, attempts: 0)
        }
        let attempts = (json["attempts"] as? Int) ?? 0
        return StoredEvent(uuid: uuid, payloadData: rawData, attempts: attempts)
    }

    /**
     Читает и валидирует событие по UUID, удаляя некорректные записи вызывающим методом.
     - Parameters:
       - uuid: Идентификатор события.
     - Returns: Сохраненное событие или nil при ошибке чтения/декодирования.
     */
    private func readEvent(uuid: String) -> StoredEvent? {
        guard let data = try? Data(contentsOf: eventUrl(uuid: uuid)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stored = parseStoredEvent(uuid: uuid, json: json, rawData: data),
              let payloadObject = try? JSONSerialization.jsonObject(with: stored.payloadData),
              payloadObject is [String: Any] else {
            return nil
        }
        return stored
    }

    /**
     Сохраняет индекс очереди на диск и сообщает результат записи.
     - Returns: Флаг успешной записи индекса.
     */
    @discardableResult
    private func persistIndex() -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: queue)
            try indexWriter(data, queueIndexUrl)
            return true
        } catch {
            ClickstreamLogger.log("OfflineEventStore: failed to write queue index: \(error)")
            return false
        }
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
     - Returns: Восстановленная очередь и следующий порядковый номер.
     */
    private static func restoreQueue(
        fileManager: FileManager,
        eventsDirectory: URL,
        maxEvents: Int
    ) -> RestoredQueue {
        let indexUrl = eventsDirectory.appendingPathComponent(indexFileName)
        guard let files = try? fileManager.contentsOfDirectory(at: eventsDirectory, includingPropertiesForKeys: nil) else {
            return RestoredQueue(uuids: [], nextSequence: initialSequence())
        }

        let records: [EventFileRecord] = files.compactMap { url in
            guard url.pathExtension == "json",
                  url.lastPathComponent != indexFileName,
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["payload"] is [String: Any] || (json["uuid"] == nil && json["attempts"] == nil) else {
                return nil
            }
            let uuid = (url.lastPathComponent as NSString).deletingPathExtension
            guard !uuid.isEmpty else { return nil }
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return EventFileRecord(
                uuid: uuid,
                sequence: (json["sequence"] as? NSNumber)?.int64Value,
                modifiedAt: modifiedAt
            )
        }

        let recordsByUUID = Dictionary(uniqueKeysWithValues: records.map { ($0.uuid, $0) })
        let indexedUUIDs: [String]? = {
            guard let data = try? Data(contentsOf: indexUrl) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String]
        }()
        var restoredRecords: [EventFileRecord]
        if let indexedUUIDs {
            let indexedRecords = indexedUUIDs.compactMap { recordsByUUID[$0] }
            let indexedSet = Set(indexedRecords.map(\.uuid))
            let maxIndexedSequence = indexedRecords.compactMap(\.sequence).max()
            let orphanRecords = records.filter { record in
                guard !indexedSet.contains(record.uuid), let sequence = record.sequence else { return false }
                return maxIndexedSequence.map { sequence > $0 } ?? true
            }
            restoredRecords = indexedRecords + sortedRecords(orphanRecords)
        } else {
            restoredRecords = sortedRecords(records)
        }

        let countLimit = max(0, maxEvents)
        restoredRecords = Array(restoredRecords.suffix(countLimit))
        let uuids = restoredRecords.map(\.uuid)
        let restoredUUIDs = Set(uuids)
        for record in records where !restoredUUIDs.contains(record.uuid) {
            try? fileManager.removeItem(at: eventsDirectory.appendingPathComponent("\(record.uuid).json"))
        }
        if let indexData = try? JSONSerialization.data(withJSONObject: uuids) {
            try? indexData.write(to: indexUrl, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let maxSequence = records.compactMap(\.sequence).max()
        let nextSequence = max(initialSequence(), maxSequence.map { $0 == Int64.max ? $0 : $0 + 1 } ?? 0)
        return RestoredQueue(uuids: uuids, nextSequence: nextSequence)
    }

    /**
     Сортирует восстановленные event-файлы по устойчивому FIFO-порядку.
     - Parameter records: Восстановленные записи событий.
     - Returns: Записи в порядке добавления в очередь.
     */
    private static func sortedRecords(_ records: [EventFileRecord]) -> [EventFileRecord] {
        records.sorted { lhs, rhs in
            switch (lhs.sequence, rhs.sequence) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return false
            case (nil, _?):
                return true
            default:
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
                return lhs.uuid < rhs.uuid
            }
        }
    }

    /**
     Возвращает начальный порядковый номер на основе текущего времени.
     - Returns: Начальный порядковый номер события.
     */
    private static func initialSequence() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000_000)
    }
}
