import Foundation
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет HTTP-запрос конфигурации флагов через FlagApiClient.
 */
final class FlagApiClientTests: XCTestCase {

    private let baseUrl = "https://gateway.example.com"
    private let apiKey = "test-api-key"
    private let deviceId = "device-42"

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
     Проверяет GET-запрос на platform endpoint флагов.
     */
    func test_fetchFlags_sendsGetToPlatformEndpoint() {
        MockFlagApiURLProtocol.responseBody = Self.sampleFlagsJSON

        let client = makeClient()
        let expectation = expectation(description: "fetchFlags completion")

        client.fetchFlags(deviceId: deviceId) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(MockFlagApiURLProtocol.requestCount, 1)
        XCTAssertEqual(MockFlagApiURLProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(
            MockFlagApiURLProtocol.lastRequest?.url?.absoluteString,
            "https://gateway.example.com/api/click-stream-rest-flag/flag/\(deviceId)"
        )
    }

    /**
     Проверяет передачу apiKey в заголовке Authorization.
     */
    func test_fetchFlags_setsAuthorizationHeader() {
        MockFlagApiURLProtocol.responseBody = Self.sampleFlagsJSON

        let client = makeClient()
        let expectation = expectation(description: "fetchFlags completion")

        client.fetchFlags(deviceId: deviceId) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(MockFlagApiURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), apiKey)
    }

    /**
     Проверяет декодирование успешного ответа backend.
     */
    func test_fetchFlags_onSuccess_decodesFlags() {
        MockFlagApiURLProtocol.responseBody = Self.sampleFlagsJSON

        let client = makeClient()
        let expectation = expectation(description: "fetchFlags completion")

        client.fetchFlags(deviceId: deviceId) { result in
            if case .success(let flags) = result {
                XCTAssertEqual(flags, [FlagInfo(id: "flag-1", name: "toggle", values: nil)])
            } else {
                XCTFail("Expected success result")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    /**
     Проверяет обработку HTTP-ошибки backend.
     */
    func test_fetchFlags_onHttpError_returnsFailure() {
        MockFlagApiURLProtocol.responseStatusCode = 500

        let client = makeClient()
        let expectation = expectation(description: "fetchFlags completion")

        client.fetchFlags(deviceId: deviceId) { result in
            if case .failure(.httpError(500)) = result {
                // expected
            } else {
                XCTFail("Expected httpError(500)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
    }

    /**
     Создает FlagApiClient с коротким таймаутом для тестов.
     */
    private func makeClient() -> FlagApiClient {
        FlagApiClient(baseUrl: baseUrl, apiKey: apiKey, requestTimeout: 1, session: makeTestSession())
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

    private static let sampleFlagsJSON = """
    [{"id":"flag-1","name":"toggle","values":null}]
    """.data(using: .utf8)!
}

/**
 Перехватывает HTTP-запросы FlagApiClient в тестах.
 */
final class MockFlagApiURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var statusCode = 200
    private nonisolated(unsafe) static var body: Data?
    private nonisolated(unsafe) static var requests = 0
    private nonisolated(unsafe) static var capturedRequest: URLRequest?

    /**
     HTTP-статус тестового ответа.
     */
    static var responseStatusCode: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return statusCode
        }
        set {
            lock.lock()
            statusCode = newValue
            lock.unlock()
        }
    }

    /**
     Тело тестового ответа.
     */
    static var responseBody: Data? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return body
        }
        set {
            lock.lock()
            body = newValue
            lock.unlock()
        }
    }

    /**
     Возвращает количество перехваченных HTTP-запросов.
     */
    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    /**
     Возвращает последний перехваченный HTTP-запрос.
     */
    static var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    /**
     Сбрасывает состояние тестового URLProtocol.
     */
    static func reset() {
        lock.lock()
        statusCode = 200
        body = nil
        requests = 0
        capturedRequest = nil
        lock.unlock()
    }

    /**
     Проверяет, должен ли URLProtocol обработать запрос.
     */
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasPrefix("/api/click-stream-rest-flag/flag") == true
    }

    /**
     Возвращает каноническую версию HTTP-запроса.
     */
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /**
     Начинает загрузку и возвращает тестовый HTTP-ответ.
     */
    override func startLoading() {
        Self.lock.lock()
        Self.capturedRequest = request
        let statusCode = Self.statusCode
        let body = Self.body
        Self.requests += 1
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    /**
     Завершает тестовую загрузку без дополнительных действий.
     */
    override func stopLoading() {}
}
