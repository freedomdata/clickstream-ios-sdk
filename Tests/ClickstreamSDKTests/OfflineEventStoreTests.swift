import Foundation
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет хранение offline-событий на диске.
 */
final class OfflineEventStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileManager: TestFileManager!

    /**
     Создает временный каталог и файловый менеджер перед каждым тестом.
     */
    override func setUpWithError() throws {
        try super.setUpWithError()
        let uniqueDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickstream-offline-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
        tempDir = uniqueDir
        fileManager = TestFileManager(applicationSupportDirectory: uniqueDir)
    }

    /**
     Удаляет временный каталог и очищает файловый менеджер после каждого теста.
     */
    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        fileManager = nil
        tempDir = nil
        try super.tearDownWithError()
    }

    /**
     Проверяет добавление события и чтение первого элемента очереди.
     */
    func testAddAndPeekReturnsStoredEvent() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)

        let newCount = store.add(payload: ["eventName": "signup", "value": 1])
        let head = try XCTUnwrap(store.peek())

        XCTAssertEqual(newCount, 1)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(head.attempts, 0)
        let json = try decodePayload(head.payloadData)
        XCTAssertEqual(json["eventName"] as? String, "signup")
        XCTAssertEqual(json["value"] as? Int, 1)
    }

    /**
     Проверяет удаление первого события в порядке FIFO.
     */
    func testRemoveFirstUsesFifoOrder() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)

        _ = store.add(payload: ["eventName": "first", "value": String(repeating: "x", count: 128)])
        _ = store.add(payload: ["eventName": "second"])

        store.removeFirst()
        let head = try XCTUnwrap(store.peek())
        let json = try decodePayload(head.payloadData)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(json["eventName"] as? String, "second")
    }

    /**
     Проверяет удаление старых событий при превышении максимального размера.
     */
    func testAddTrimsQueueWhenMaxReached() throws {
        let store = OfflineEventStore(maxEvents: 2, fileManager: fileManager)

        _ = store.add(payload: ["eventName": "one"])
        _ = store.add(payload: ["eventName": "two"])
        _ = store.add(payload: ["eventName": "three"])

        let first = try XCTUnwrap(store.peek())
        let firstJson = try decodePayload(first.payloadData)
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(firstJson["eventName"] as? String, "two")

        store.removeFirst()
        let second = try XCTUnwrap(store.peek())
        let secondJson = try decodePayload(second.payloadData)
        XCTAssertEqual(secondJson["eventName"] as? String, "three")
    }

    /**
     Проверяет сохранение нового количества попыток отправки.
     */
    func testUpdateAttemptsPersistsNewAttemptsValue() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "retry_me"])
        let head = try XCTUnwrap(store.peek())

        store.updateAttempts(uuid: head.uuid, newAttempts: 3)
        let updated = try XCTUnwrap(store.peek())

        XCTAssertEqual(updated.uuid, head.uuid)
        XCTAssertEqual(updated.attempts, 3)
    }

    /**
     Проверяет увеличение attempts без переполнения максимального значения Int.
     */
    func testUpdateAttemptsForBatchUsesSaturatingIncrement() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "retry_me"])
        let head = try XCTUnwrap(store.peek())
        store.updateAttempts(uuid: head.uuid, newAttempts: Int.max)
        let saturated = try XCTUnwrap(store.peek())

        let maxAttempts = store.updateAttempts(for: [saturated])
        let updated = try XCTUnwrap(store.peek())

        XCTAssertEqual(maxAttempts, Int.max)
        XCTAssertEqual(updated.attempts, Int.max)
    }

    /**
     Проверяет пропуск поврежденного первого файла события.
     */
    func testPeekSkipsCorruptedHeadFileAndReturnsNextEvent() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "broken"])
        _ = store.add(payload: ["eventName": "valid"])
        let first = try XCTUnwrap(store.peek())

        let firstPath = eventsDirectory()
            .appendingPathComponent("\(first.uuid).json")
        try Data("not-json".utf8).write(to: firstPath)

        let repairedHead = try XCTUnwrap(store.peek())
        let repairedJson = try decodePayload(repairedHead.payloadData)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(repairedJson["eventName"] as? String, "valid")
    }

    /**
     Проверяет восстановление очереди из индекса между экземплярами.
     */
    func testRestoreQueueFromIndexAcrossInstances() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "restored_one"])
        _ = store.add(payload: ["eventName": "restored_two"])

        let restored = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        let head = try XCTUnwrap(restored.peek())
        let json = try decodePayload(head.payloadData)

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(json["eventName"] as? String, "restored_one")
    }

    /**
     Проверяет rollback event-файла при ошибке сохранения индекса.
     */
    func testAddRollsBackWhenIndexWriteFails() throws {
        let store = OfflineEventStore(
            maxEvents: 10,
            fileManager: fileManager,
            indexWriter: { _, _ in throw TestIndexWriteError.failed }
        )

        XCTAssertFalse(store.addAndReport(payload: ["eventName": "not_persisted"]))
        XCTAssertEqual(store.count, 0)

        let eventFiles = try FileManager.default.contentsOfDirectory(
            at: eventsDirectory(),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" && $0.lastPathComponent != "queue_index.json" }
        XCTAssertTrue(eventFiles.isEmpty)
    }

    /**
     Проверяет восстановление orphan event-файла после валидного старого индекса.
     */
    func testRestoreQueueMergesNewerOrphanInFifoOrder() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "indexed"])
        let indexed = try XCTUnwrap(store.peek())
        let indexedSequence = try XCTUnwrap(indexed.sequence)
        let orphanUUID = "orphan-event"
        let orphanData = try JSONSerialization.data(withJSONObject: [
            "uuid": orphanUUID,
            "payload": ["eventName": "orphan"],
            "attempts": 0,
            "sequence": indexedSequence + 1
        ])
        try orphanData.write(to: eventsDirectory().appendingPathComponent("\(orphanUUID).json"), options: .atomic)

        let restored = OfflineEventStore(maxEvents: 10, fileManager: fileManager)

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(try decodePayload(XCTUnwrap(restored.peek()).payloadData)["eventName"] as? String, "indexed")
        restored.removeFirst()
        XCTAssertEqual(try decodePayload(XCTUnwrap(restored.peek()).payloadData)["eventName"] as? String, "orphan")
    }

    /**
     Проверяет восстановление очереди из файлов при отсутствии индекса.
     */
    func testRestoreQueueWithoutIndexBuildsQueueFromEventFiles() throws {
        let eventsDir = eventsDirectory()
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        try payloadData(eventName: "a").write(to: eventsDir.appendingPathComponent("a.json"))
        try payloadData(eventName: "b").write(to: eventsDir.appendingPathComponent("b.json"))
        try payloadData(eventName: "c").write(to: eventsDir.appendingPathComponent("c.json"))

        let restored = OfflineEventStore(maxEvents: 2, fileManager: fileManager)
        let head = try XCTUnwrap(restored.peek())
        let json = try decodePayload(head.payloadData)

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(json["eventName"] as? String, "b")
    }

    /**
     Проверяет FIFO-выборку batch по максимальному количеству событий.
     */
    func testBatchRespectsCountLimit() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "first"])
        _ = store.add(payload: ["eventName": "second"])
        _ = store.add(payload: ["eventName": "third"])

        let batch = store.batch(maxCount: 2)

        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(try decodePayload(batch[0].payloadData)["eventName"] as? String, "first")
        XCTAssertEqual(try decodePayload(batch[1].payloadData)["eventName"] as? String, "second")
    }

    /**
     Проверяет удаление подтвержденных UUID без изменения порядка остальных событий.
     */
    func testRemoveUUIDsKeepsUnconfirmedEventsInOrder() throws {
        let store = OfflineEventStore(maxEvents: 10, fileManager: fileManager)
        _ = store.add(payload: ["eventName": "first"])
        _ = store.add(payload: ["eventName": "second"])
        _ = store.add(payload: ["eventName": "third"])
        let events = store.batch(maxCount: 3)

        store.remove(uuids: [events[0].uuid, events[2].uuid])

        let remaining = try XCTUnwrap(store.peek())
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(try decodePayload(remaining.payloadData)["eventName"] as? String, "second")
    }

    /**
     Декодирует JSON-данные payload в словарь.
     - Parameters:
       - data: JSON-данные payload.
     - Returns: Словарь payload.
     */
    private func decodePayload(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /**
     Возвращает каталог файлов offline-событий.
     - Returns: URL каталога событий.
     */
    private func eventsDirectory() -> URL {
        tempDir.appendingPathComponent("com.clickstream.sdk/events", isDirectory: true)
    }

    /**
     Создает JSON-данные payload с именем события.
     - Parameters:
       - eventName: Имя события.
     - Returns: JSON-данные payload.
     */
    private func payloadData(eventName: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["eventName": eventName])
    }
}

private enum TestIndexWriteError: Error {
    case failed
}

/**
 Подменяет каталог Application Support для тестов.
 */
private final class TestFileManager: FileManager, @unchecked Sendable {
    private let applicationSupportDirectory: URL

    /**
     Создает файловый менеджер с тестовым каталогом Application Support.
     - Parameters:
       - applicationSupportDirectory: Тестовый каталог Application Support.
     */
    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    /**
     Возвращает тестовый каталог для Application Support.
     - Parameters:
       - directory: Запрашиваемый системный каталог.
       - domainMask: Область поиска системного каталога.
     - Returns: Массив URL для запрошенного каталога.
     */
    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .applicationSupportDirectory {
            return [applicationSupportDirectory]
        }
        return super.urls(for: directory, in: domainMask)
    }
}
