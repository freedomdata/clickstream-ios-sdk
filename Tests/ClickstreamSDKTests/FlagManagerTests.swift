import Foundation
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет менеджер конфигурации флагов.
 */
final class FlagManagerTests: XCTestCase {

    private let deviceId = "test-device-\(UUID().uuidString)"

    /**
     Регистрирует мок HTTP перед каждым тестом.
     */
    override func setUpWithError() throws {
        try super.setUpWithError()
        MockFlagApiURLProtocol.reset()
    }

    /**
     Снимает мок HTTP после каждого теста.
     */
    override func tearDownWithError() throws {
        MockFlagApiURLProtocol.reset()
        try super.tearDownWithError()
    }

    /**
     Проверяет чтение конфигурации из локального хранилища при инициализации.
     */
    func test_getFlags_returnsStoredConfiguration() {
        let storage = FlagStorage()
        let flags = [FlagInfo(id: "flag-1", name: "toggle", values: nil)]
        XCTAssertTrue(storage.save(flags: flags, deviceId: deviceId))

        let manager = FlagManager(
            baseUrl: "https://example.com",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage
        )

        XCTAssertEqual(manager.getFlags(), flags)
    }

    /**
     Проверяет fallback к локальному cache при ошибке запроса.
     */
    func test_fetchFlags_onFailure_returnsStoredFallbackWithoutOverwriting() {
        let storage = FlagStorage()
        let storedFlags = [
            FlagInfo(
                id: "flag-1",
                name: "button",
                values: [FlagValue(id: "value-1", value: "cached", isDefault: true, conditions: nil)]
            )
        ]
        XCTAssertTrue(storage.save(flags: storedFlags, deviceId: deviceId))

        let manager = FlagManager(
            baseUrl: "https://invalid.example",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: StubFlagFetcher(result: .failure(.requestFailed))
        )

        let expectation = expectation(description: "fetchFlags completion")
        manager.fetchFlags { result in
            if case .fallback(let flags) = result {
                XCTAssertEqual(flags, storedFlags)
            } else {
                XCTFail("Expected fallback result")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(manager.getFlags(), storedFlags)
        XCTAssertEqual(storage.load(deviceId: deviceId), storedFlags)
    }

    /**
     Проверяет success и обновление in-memory cache при ошибке записи новой конфигурации.
     */
    func test_fetchFlags_onPersistenceFailure_returnsSuccessAndUpdatesMemory() {
        let storedFlags = [
            FlagInfo(id: "flag-1", name: "cached", values: nil)
        ]
        let freshFlags = [
            FlagInfo(id: "flag-2", name: "new", values: nil)
        ]
        let storage = FailingFlagStorage(storedFlags: storedFlags, shouldFailSave: true)

        let manager = FlagManager(
            baseUrl: "https://example.com",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: StubFlagFetcher(result: .success(freshFlags))
        )

        let expectation = expectation(description: "fetchFlags completion")
        manager.fetchFlags { result in
            if case .success(let flags) = result {
                XCTAssertEqual(flags, freshFlags)
            } else {
                XCTFail("Expected success result")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(manager.getFlags(), freshFlags)
        XCTAssertEqual(storage.load(deviceId: deviceId), storedFlags)
        XCTAssertEqual(storage.loadPending(deviceId: deviceId), freshFlags)
    }

    /**
     Проверяет fallback к обновленному in-memory cache после ошибки записи.
     */
    func test_fetchFlags_afterPersistenceFailure_networkFallbackUsesUpdatedMemory() {
        let storedFlags = [
            FlagInfo(id: "flag-1", name: "cached", values: nil)
        ]
        let freshFlags = [
            FlagInfo(id: "flag-2", name: "new", values: nil)
        ]
        let storage = FailingFlagStorage(storedFlags: storedFlags, shouldFailSave: true)

        let manager = FlagManager(
            baseUrl: "https://example.com",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: StubFlagFetcher(result: .success(freshFlags))
        )

        let firstFetch = expectation(description: "first fetchFlags completion")
        manager.fetchFlags { _ in
            firstFetch.fulfill()
        }
        wait(for: [firstFetch], timeout: 1)

        let managerAfterFailure = FlagManager(
            baseUrl: "https://example.com",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: StubFlagFetcher(result: .failure(.requestFailed))
        )

        let secondFetch = expectation(description: "second fetchFlags completion")
        managerAfterFailure.fetchFlags { result in
            if case .fallback(let flags) = result {
                XCTAssertEqual(flags, freshFlags)
            } else {
                XCTFail("Expected fallback result")
            }
            secondFetch.fulfill()
        }

        wait(for: [secondFetch], timeout: 1)
        XCTAssertEqual(managerAfterFailure.getFlags(), freshFlags)
    }

    /**
     Проверяет восстановление pending-конфигурации после restart.
     */
    func test_init_withPendingFlags_prefersPendingOverStored() {
        let storage = FlagStorage()
        let storedFlags = [FlagInfo(id: "flag-1", name: "old", values: nil)]
        let pendingFlags = [FlagInfo(id: "flag-2", name: "new", values: nil)]

        XCTAssertTrue(storage.save(flags: storedFlags, deviceId: deviceId))
        XCTAssertTrue(storage.savePending(flags: pendingFlags, deviceId: deviceId))

        let manager = FlagManager(
            baseUrl: "https://example.com",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: StubFlagFetcher(result: .failure(.requestFailed))
        )

        XCTAssertEqual(manager.getFlags(), pendingFlags)
    }

    /**
     Проверяет повторную запись конфигурации после временной ошибки persistence.
     */
    /* func test_fetchFlags_onPersistenceFailure_retriesUntilSaved() {
        let storedFlags = [FlagInfo(id: "flag-1", name: "cached", values: nil)]
        let freshFlags = [FlagInfo(id: "flag-2", name: "new", values: nil)]
        let storage = FailingFlagStorage(storedFlags: storedFlags, remainingSaveFailures: 1)

        let manager = FlagManager(
            baseUrl: "https://example.com",
            apiKey: "test-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: StubFlagFetcher(result: .success(freshFlags))
        )

        let fetchExpectation = expectation(description: "fetchFlags completion")
        manager.fetchFlags { result in
            if case .success(let flags) = result {
                XCTAssertEqual(flags, freshFlags)
            } else {
                XCTFail("Expected success result")
            }
            fetchExpectation.fulfill()
        }

        wait(for: [fetchExpectation], timeout: 1)

        let persistedExpectation = expectation(description: "flags persisted")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            if storage.load(deviceId: self.deviceId) == freshFlags,
               storage.loadPending(deviceId: self.deviceId) == nil {
                persistedExpectation.fulfill()
            }
        }

        wait(for: [persistedExpectation], timeout: 4)
    } */

    /**
     Проверяет успешный REST-запрос, обновление in-memory cache и локального хранилища.
     */
    func test_fetchFlags_onSuccess_persistsToLocalCache() {
        let expectedFlags = [FlagInfo(id: "flag-1", name: "toggle", values: nil)]
        MockFlagApiURLProtocol.responseBody = """
        [{"id":"flag-1","name":"toggle","values":null}]
        """.data(using: .utf8)

        let storage = FlagStorage()
        let session = makeTestSession()
        let manager = FlagManager(
            baseUrl: "https://gateway.example.com",
            apiKey: "test-api-key",
            deviceId: deviceId,
            storage: storage,
            apiClient: FlagApiClient(
                baseUrl: "https://gateway.example.com",
                apiKey: "test-api-key",
                requestTimeout: 1,
                session: session
            )
        )

        let expectation = expectation(description: "fetchFlags completion")
        manager.fetchFlags { result in
            if case .success(let flags) = result {
                XCTAssertEqual(flags, expectedFlags)
            } else {
                XCTFail("Expected success result")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(manager.getFlags(), expectedFlags)
        XCTAssertEqual(storage.load(deviceId: deviceId), expectedFlags)
        XCTAssertNil(storage.loadPending(deviceId: deviceId))
        XCTAssertEqual(
            MockFlagApiURLProtocol.lastRequest?.url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest-flag/flag/\(deviceId)"
        )
        XCTAssertEqual(
            MockFlagApiURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "test-api-key"
        )
    }

    /**
     Создает URLSession с перехватом HTTP через URLProtocol.
     */
    private func makeTestSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockFlagApiURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

private final class FailingFlagStorage: FlagStoring {
    private var storedFlags: [FlagInfo]?
    private var pendingFlags: [FlagInfo]?
    private var remainingSaveFailures: Int

    init(storedFlags: [FlagInfo]?, remainingSaveFailures: Int) {
        self.storedFlags = storedFlags
        self.remainingSaveFailures = remainingSaveFailures
    }

    convenience init(storedFlags: [FlagInfo]?, shouldFailSave: Bool) {
        self.init(storedFlags: storedFlags, remainingSaveFailures: shouldFailSave ? .max : 0)
    }

    func save(flags: [FlagInfo], deviceId: String) -> Bool {
        guard remainingSaveFailures <= 0 else {
            remainingSaveFailures -= 1
            return false
        }
        storedFlags = flags
        pendingFlags = nil
        return true
    }

    func load(deviceId: String) -> [FlagInfo]? {
        storedFlags
    }

    func savePending(flags: [FlagInfo], deviceId: String) -> Bool {
        pendingFlags = flags
        return true
    }

    func loadPending(deviceId: String) -> [FlagInfo]? {
        pendingFlags
    }

    func clearPending(deviceId: String) {
        pendingFlags = nil
    }
}

private final class StubFlagFetcher: FlagFetching {
    private let result: FlagApiClient.FetchResult

    init(result: FlagApiClient.FetchResult) {
        self.result = result
    }

    func fetchFlags(deviceId: String, completion: @escaping @Sendable (FlagApiClient.FetchResult) -> Void) {
        completion(result)
    }
}
