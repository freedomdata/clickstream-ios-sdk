import XCTest
@testable import ClickstreamSDK

/**
 Проверяет локальное хранение конфигурации флагов.
 */
final class FlagStorageTests: XCTestCase {

    private let deviceId = "test-device-\(UUID().uuidString)"

    /**
     Проверяет сохранение и чтение конфигурации флагов.
     */
    func test_saveAndLoad_roundTrip() {
        let storage = FlagStorage()
        let flags = [
            FlagInfo(
                id: "flag-1",
                name: "button",
                values: [
                    FlagValue(id: "value-1", value: "A", isDefault: true, conditions: nil)
                ]
            )
        ]

        XCTAssertTrue(storage.save(flags: flags, deviceId: deviceId))
        let loaded = storage.load(deviceId: deviceId)

        XCTAssertEqual(loaded, flags)
    }

    /**
     Проверяет отсутствие данных для неизвестного deviceId.
     */
    func test_load_unknownDeviceId_returnsNil() {
        let storage = FlagStorage()
        XCTAssertNil(storage.load(deviceId: "unknown-\(UUID().uuidString)"))
    }

    /**
     Проверяет сохранение и чтение pending-конфигурации флагов.
     */
    func test_savePendingAndLoad_roundTrip() {
        let storage = FlagStorage()
        let flags = [FlagInfo(id: "flag-1", name: "pending", values: nil)]

        XCTAssertTrue(storage.savePending(flags: flags, deviceId: deviceId))
        XCTAssertEqual(storage.loadPending(deviceId: deviceId), flags)
    }

    /**
     Проверяет приоритет pending-конфигурации при чтении best available.
     */
    func test_loadBestAvailable_prefersPendingOverStored() {
        let storage = FlagStorage()
        let storedFlags = [FlagInfo(id: "flag-1", name: "stored", values: nil)]
        let pendingFlags = [FlagInfo(id: "flag-2", name: "pending", values: nil)]

        XCTAssertTrue(storage.save(flags: storedFlags, deviceId: deviceId))
        XCTAssertTrue(storage.savePending(flags: pendingFlags, deviceId: deviceId))

        XCTAssertEqual(storage.loadBestAvailable(deviceId: deviceId), pendingFlags)
    }

    /**
     Проверяет очистку pending-конфигурации после успешного save.
     */
    func test_save_clearsPendingSnapshot() {
        let storage = FlagStorage()
        let flags = [FlagInfo(id: "flag-1", name: "stored", values: nil)]

        XCTAssertTrue(storage.savePending(flags: flags, deviceId: deviceId))
        XCTAssertTrue(storage.save(flags: flags, deviceId: deviceId))

        XCTAssertNil(storage.loadPending(deviceId: deviceId))
        XCTAssertEqual(storage.load(deviceId: deviceId), flags)
    }
}
