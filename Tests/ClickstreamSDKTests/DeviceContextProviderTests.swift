import XCTest
@testable import ClickstreamSDK

/**
 Проверяет сбор параметров устройства и окружения.
 */
final class DeviceContextProviderTests: XCTestCase {

    private var networkMonitor: NetworkMonitor!

    /**
     Создает монитор сети перед каждым тестом.
     */
    override func setUp() {
        super.setUp()
        networkMonitor = NetworkMonitor()
    }

    /**
     Проверяет пустой результат при отключенном deviceContext.
     */
    func test_getParams_whenDeviceContextDisabled_returnsEmpty() {
        let provider = DeviceContextProvider(
            trackingOptionsProvider: { TrackingOptions(disabledFields: [.deviceContext]) },
            networkMonitor: networkMonitor,
            sdkVersion: "1.0.0"
        )
        let params = provider.getParams()
        XCTAssertTrue(params.isEmpty)
    }

    /**
     Проверяет непустой результат при включенном deviceContext.
     */
    func test_getParams_whenDeviceContextEnabled_returnsNonEmpty() {
        let provider = DeviceContextProvider(
            trackingOptionsProvider: { TrackingOptions() },
            networkMonitor: networkMonitor,
            sdkVersion: "2.0.0"
        )
        let params = provider.getParams()
        XCTAssertFalse(params.isEmpty)
        XCTAssertEqual(params["sdkVersion"] as? String, "2.0.0")
    }

    /**
     Проверяет применение актуальных TrackingOptions при каждом вызове.
     */
    func test_getParams_respectsTrackingOptionsProvider() {
        var returnDisabled = true
        let provider = DeviceContextProvider(
            trackingOptionsProvider: {
                returnDisabled ? TrackingOptions(disabledFields: [.deviceContext]) : TrackingOptions()
            },
            networkMonitor: networkMonitor,
            sdkVersion: "1.0"
        )
        XCTAssertTrue(provider.getParams().isEmpty)
        returnDisabled = false
        XCTAssertFalse(provider.getParams().isEmpty)
    }

    /**
     Проверяет наличие ожидаемых ключей при включенном deviceContext.
     */
    func test_getParams_includesExpectedKeysWhenEnabled() {
        let provider = DeviceContextProvider(
            trackingOptionsProvider: { TrackingOptions() },
            networkMonitor: networkMonitor,
            sdkVersion: "0.0.0"
        )
        let params = provider.getParams()
        let osName: Any? = params["osName"] ?? nil
        XCTAssertNotNil(osName)
        XCTAssertEqual(osName as? String, "iOS")

        let networkType: Any? = params["networkType"] ?? nil
        XCTAssertTrue(networkType == nil || networkType is String)

        let sdkVersion: Any? = params["sdkVersion"] ?? nil
        XCTAssertNotNil(sdkVersion)
    }
}