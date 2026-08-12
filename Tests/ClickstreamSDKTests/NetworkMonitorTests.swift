import XCTest
@testable import ClickstreamSDK

/**
 Проверяет определение состояния и типа сети.
 */
final class NetworkMonitorTests: XCTestCase {

    /**
     Проверяет создание NetworkMonitor без падения.
     */
    func test_init_doesNotCrash() {
        _ = NetworkMonitor()
    }

    /**
     Проверяет, что тип сети возвращается строкой или nil.
     */
    func test_getNetworkType_returnsStringOrNil() {
        let monitor = NetworkMonitor()
        let type = monitor.getNetworkType()
        XCTAssertTrue(type == nil || !type!.isEmpty)
    }

    /**
     Проверяет, что тип сети входит в список допустимых значений.
     */
    func test_getNetworkType_returnsValidTypeOrNil() {
        let monitor = NetworkMonitor()
        let type = monitor.getNetworkType()
        let valid: [String] = ["wifi", "cellular", "ethernet", "none"]
        if let type {
            XCTAssertTrue(valid.contains(type), "Expected one of \(valid), got '\(type)'")
        }
    }

    /**
     Проверяет согласованность типа сети при повторных вызовах.
     */
    func test_getNetworkType_multipleCalls_consistent() {
        let monitor = NetworkMonitor()
        let a = monitor.getNetworkType()
        let b = monitor.getNetworkType()
        if let a, let b {
            XCTAssertEqual(a, b)
        }
    }
}