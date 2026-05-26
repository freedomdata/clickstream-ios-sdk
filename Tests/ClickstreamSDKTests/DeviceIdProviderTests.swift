import XCTest
@testable import ClickstreamSDK

/**
 Проверяет получение уникального идентификатора устройства.
 */
final class DeviceIdProviderTests: XCTestCase {

    /**
     Проверяет, что deviceId не пустой и имеет формат UUID.
     */
    func test_getDeviceId_returnsNonEmpty() {
        let provider = DeviceIdProvider()
        let id = provider.getDeviceId()
        XCTAssertFalse(id.isEmpty)
        XCTAssertEqual(id.count, 36)
    }

    /**
     Проверяет, что повторный вызов возвращает тот же deviceId.
     */
    func test_getDeviceId_returnsSameValueOnSecondCall() {
        let provider = DeviceIdProvider()
        let id1 = provider.getDeviceId()
        let id2 = provider.getDeviceId()
        XCTAssertEqual(id1, id2)
    }
}