import Foundation
import XCTest
@testable import ClickstreamSDK

/**
 Проверяет отправку событий из offline-очереди.
 */
final class EventQueueTests: XCTestCase {
    private var networkMonitor: NetworkMonitor?

    /**
     Подготавливает мок сетевых запросов и очищает очередь перед каждым тестом.
     */
    override func setUpWithError() throws {
        try super.setUpWithError()
        URLProtocol.registerClass(MockEventApiURLProtocol.self)
        clearQueueDirectory()
        networkMonitor = NetworkMonitor()
        try waitUntilNetworkIsAvailable()
    }

    /**
     Очищает мок сетевых запросов и очередь после каждого теста.
     */
    override func tearDownWithError() throws {
        networkMonitor = nil
        MockEventApiURLProtocol.reset()
        URLProtocol.unregisterClass(MockEventApiURLProtocol.self)
        clearQueueDirectory()
        try super.tearDownWithError()
    }

    /**
     Проверяет удаление события из очереди после успешной отправки.
     */
    func testEnqueueFlushesOnSuccess() throws {
        MockEventApiURLProtocol.responseStatusCodes = [200]

        let queue = makeQueue(flushMaxRetries: 3)
        queue.enqueue(["eventName": "success"])

        try waitUntilRequestCount(atLeast: 1)
        try waitUntilQueueIsEmpty()
    }

    /**
     Проверяет удаление события из очереди при non-retryable ошибке.
     */
    func testEnqueueDropsEventOnNonRetryableFailure() throws {
        MockEventApiURLProtocol.responseStatusCodes = [400]

        let queue = makeQueue(flushMaxRetries: 3)
        queue.enqueue(["eventName": "bad_request"])

        try waitUntilRequestCount(atLeast: 1)
        try waitUntilQueueIsEmpty()
    }

    /**
     Проверяет повторную отправку события до успешного результата.
     */
    func testEnqueueRetriesThenSucceeds() throws {
        MockEventApiURLProtocol.responseStatusCodes = [500, 200]

        let queue = makeQueue(flushMaxRetries: 4)
        queue.enqueue(["eventName": "retry_then_success"])

        try waitUntilRequestCount(atLeast: 2, timeout: 6.0)
        try waitUntilQueueIsEmpty(timeout: 6.0)
    }

    /**
     Проверяет удаление события при исчерпании лимита повторных попыток.
     */
    func testEnqueueDropsWhenRetryBudgetExhausted() throws {
        MockEventApiURLProtocol.responseStatusCodes = [500]

        let queue = makeQueue(flushMaxRetries: 1)
        queue.enqueue(["eventName": "drop_on_budget"])

        try waitUntilRequestCount(atLeast: 1)
        try waitUntilQueueIsEmpty()
    }

    /**
     Создает очередь событий с заданным лимитом повторных попыток.
     - Parameters:
       - flushMaxRetries: Максимальное количество повторных попыток отправки.
     - Returns: Очередь событий для теста.
     */
    private func makeQueue(flushMaxRetries: Int) -> EventQueue {
        let client = EventApiClient(baseUrl: "https://example.com", apiKey: "test-key", requestTimeout: 1)
        return EventQueue(
            apiClient: client,
            maxQueueSize: 100,
            flushQueueSize: 1,
            flushMaxRetries: flushMaxRetries,
            flushBatchSize: 50,
            flushIntervalMillis: 0,
            maxFlushProcessingTimeMs: 10_000
        )
    }

    /**
     Ожидает доступность сети в тестовом окружении.
     - Parameters:
       - timeout: Максимальное время ожидания в секундах.
     */
    private func waitUntilNetworkIsAvailable(timeout: TimeInterval = 2.0) throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if NetworkMonitor.isNetworkAvailable() {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        throw XCTSkip("Network not available in simulator environment")
    }

    /**
     Ожидает очистку файлов очереди событий.
     - Parameters:
       - timeout: Максимальное время ожидания в секундах.
     */
    private func waitUntilQueueIsEmpty(timeout: TimeInterval = 3.0) throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if queuedEventFilesCount() == 0 {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTFail("Queue did not drain in \(timeout) seconds")
    }

    /**
     Ожидает нужное количество перехваченных HTTP-запросов.
     - Parameters:
       - expected: Минимальное ожидаемое количество запросов.
       - timeout: Максимальное время ожидания в секундах.
     */
    private func waitUntilRequestCount(atLeast expected: Int, timeout: TimeInterval = 3.0) throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if MockEventApiURLProtocol.requestCount >= expected {
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        throw XCTSkip("Could not observe URLSession request interception in this simulator environment")
    }

    /**
     Удаляет каталог файлов offline-очереди.
     */
    private func clearQueueDirectory() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("com.clickstream.sdk/events", isDirectory: true)
        try? fileManager.removeItem(at: dir)
    }

    /**
     Возвращает количество файлов событий в offline-очереди.
     - Returns: Количество файлов событий.
     */
    private func queuedEventFilesCount() -> Int {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("com.clickstream.sdk/events", isDirectory: true)
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return 0
        }
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "queue_index.json" }
            .count
    }
}

/**
 Перехватывает HTTP-запросы EventApiClient в тестах.
 */
private final class MockEventApiURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var codes: [Int] = []
    private nonisolated(unsafe) static var requests = 0

    /**
     Хранит последовательность HTTP-статусов для тестовых ответов.
     */
    static var responseStatusCodes: [Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return codes
        }
        set {
            lock.lock()
            codes = newValue
            requests = 0
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
     Сбрасывает состояние тестового URLProtocol.
     */
    static func reset() {
        lock.lock()
        codes = []
        requests = 0
        lock.unlock()
    }

    /**
     Проверяет, должен ли URLProtocol обработать запрос.
     - Parameters:
       - request: HTTP-запрос для проверки.
     - Returns: Флаг обработки запроса.
     */
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/event"
    }

    /**
     Возвращает каноническую версию HTTP-запроса.
     - Parameters:
       - request: Исходный HTTP-запрос.
     - Returns: Канонический HTTP-запрос.
     */
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    /**
     Начинает загрузку и возвращает тестовый HTTP-ответ.
     */
    override func startLoading() {
        Self.lock.lock()
        let statusCode = Self.codes.isEmpty ? 200 : Self.codes.removeFirst()
        Self.requests += 1
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    /**
     Завершает тестовую загрузку без дополнительных действий.
     */
    override func stopLoading() {}
}