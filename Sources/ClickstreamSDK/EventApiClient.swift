import Foundation

/**
 Отправляет события в Clickstream API.
 */
internal final class EventApiClient {
    private static let dataCollectionDisabledMessage = "Data collection is disabled"
    private static let maxResponseMessageLength = 200
    private let baseUrl: String
    private let apiKey: String
    private let session: URLSession
    private let requestTimeout: TimeInterval

    /**
     Создает клиент для отправки событий в Clickstream API.
     - Parameters:
       - baseUrl: Базовый URL Clickstream API.
       - apiKey: Ключ авторизации запросов.
       - requestTimeout: Таймаут запроса в секундах.
       - session: Пользовательская URLSession для выполнения запросов.
     */
    init(
        baseUrl: String,
        apiKey: String,
        requestTimeout: TimeInterval = 60,
        session: URLSession? = nil
    ) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.requestTimeout = requestTimeout
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout + 30
        configuration.timeoutIntervalForResource = requestTimeout + 30
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /**
     Отправляет событие в legacy endpoint.
     - Parameters:
       - payload: Данные события.
       - completion: Замыкание с результатом отправки.
     */
    func sendEvent(_ payload: [String: Any], completion: (@Sendable (QueueSendResult) -> Void)? = nil) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            ClickstreamLogger.log("Failed to serialize event payload.")
            completion?(.nonRetryableFailure)
            return
        }
        guard let url = ClickstreamURLBuilder.eventEndpointURL(baseUrl: baseUrl) else {
            ClickstreamLogger.log("Invalid URL: \(ClickstreamURLBuilder.eventEndpointDescription(baseUrl: baseUrl))")
            completion?(.nonRetryableFailure)
            return
        }
        let request = makeRequest(url: url, body: jsonData)
        let gate = EventApiCompletionGate()
        let deadline = Date().addingTimeInterval(requestTimeout)
        let task = session.dataTask(with: request) { _, response, error in
            guard gate.claim() else { return }
            if Date() >= deadline || (error as? URLError)?.code == .timedOut {
                completion?(.retryableFailure)
                return
            }
            guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                completion?(.retryableFailure)
                return
            }
            let code = httpResponse.statusCode
            if (200..<300).contains(code) { completion?(.success) }
            else if code == 429 || (500..<600).contains(code) { completion?(.retryableFailure) }
            else { completion?(.nonRetryableFailure) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requestTimeout) {
            guard gate.claim() else { task.cancel(); return }
            task.cancel()
            completion?(.retryableFailure)
        }
        task.resume()
    }

    /**
     Отправляет JSON-массив объектов через batch endpoint.
     - Parameters:
       - payloads: JSON-данные событий.
       - completion: Замыкание с результатом batch-запроса.
     */
    func sendBatch(_ payloads: [Data], completion: @escaping @Sendable (BatchSendResult) -> Void) {
        guard !payloads.isEmpty,
              payloads.allSatisfy({
                  guard let object = try? JSONSerialization.jsonObject(with: $0) else { return false }
                  return object is [String: Any]
              }) else {
            completion(.retryableFailure(retryAfterSeconds: nil))
            return
        }
        guard let url = ClickstreamURLBuilder.batchEventEndpointURL(baseUrl: baseUrl) else {
            ClickstreamLogger.log("Invalid URL: \(ClickstreamURLBuilder.batchEventEndpointDescription(baseUrl: baseUrl))")
            completion(.nonRetryableTransportFailure)
            return
        }
        var body = Data("[".utf8)
        for (index, payload) in payloads.enumerated() {
            if index > 0 { body.append(contentsOf: Data(",".utf8)) }
            body.append(payload)
        }
        body.append(contentsOf: Data("]".utf8))
        let request = makeRequest(url: url, body: body)
        let gate = EventApiCompletionGate()
        let deadline = Date().addingTimeInterval(requestTimeout)
        let task = session.dataTask(with: request) { data, response, error in
            guard gate.claim() else { return }
            if let error {
                if NetworkErrorClassifier.isRetryable(error) {
                    completion(.retryableFailure(retryAfterSeconds: nil))
                } else {
                    completion(.nonRetryableTransportFailure)
                }
                return
            }
            if Date() >= deadline {
                completion(.retryableFailure(retryAfterSeconds: nil))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.retryableFailure(retryAfterSeconds: nil))
                return
            }
            let code = httpResponse.statusCode
            if (200..<300).contains(code) {
                guard let results = Self.parseBatchResults(data: data, batchSize: payloads.count) else {
                    completion(.retryableFailure(retryAfterSeconds: nil))
                    return
                }
                completion(.processed(results: results))
            } else if code == 429 || (500..<600).contains(code) {
                completion(.retryableFailure(retryAfterSeconds: Self.retryAfterSeconds(from: httpResponse)))
            } else if (400..<500).contains(code) {
                completion(.nonRetryableHTTPFailure(statusCode: code))
            } else {
                completion(.retryableFailure(retryAfterSeconds: Self.retryAfterSeconds(from: httpResponse)))
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requestTimeout) {
            guard gate.claim() else { task.cancel(); return }
            task.cancel()
            completion(.retryableFailure(retryAfterSeconds: nil))
        }
        task.resume()
    }

    /**
     Формирует POST request с общими заголовками API.
     - Parameters:
       - url: URL endpoint-а.
       - body: Тело HTTP-запроса.
     - Returns: Подготовленный POST request.
     */
    private func makeRequest(url: URL, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout + 30
        request.httpBody = body
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        return request
    }

    /**
     Разбирает валидные результаты batch-ответа и подтверждение отключенного сбора данных.
     - Parameters:
       - data: Тело batch-ответа.
       - batchSize: Количество событий в отправленном batch.
     - Returns: Валидные результаты событий или nil для некорректного ответа.
     */
    private static func parseBatchResults(data: Data?, batchSize: Int) -> [BatchEventResult]? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }
        guard let rawResultValues = root["results"] as? [Any] else {
            guard normalizedMessage(root["message"] as? String) == dataCollectionDisabledMessage else {
                return nil
            }
            return (0..<batchSize).map {
                BatchEventResult(index: $0, status: .skipped, message: dataCollectionDisabledMessage)
            }
        }
        guard let rawResults = rawResultValues as? [[String: Any]] else { return nil }
        var resultsByIndex: [Int: BatchEventResult] = [:]
        var conflictingIndices = Set<Int>()
        for raw in rawResults {
            guard let index = raw["index"] as? Int,
                  index >= 0,
                  let statusValue = raw["status"] as? String,
                  let status = BatchEventStatus(rawValue: statusValue),
                  !conflictingIndices.contains(index) else { continue }
            if let existing = resultsByIndex[index] {
                if existing.status != status {
                    resultsByIndex[index] = nil
                    conflictingIndices.insert(index)
                }
                continue
            }
            resultsByIndex[index] = BatchEventResult(
                index: index,
                status: status,
                message: raw["message"] as? String
            )
        }
        return resultsByIndex.values.sorted { $0.index < $1.index }
    }

    /**
     Нормализует диагностическое сообщение backend-а для безопасного сравнения.
     - Parameter message: Исходное сообщение backend-а.
     - Returns: Однострочное непустое сообщение ограниченной длины или nil.
     */
    private static func normalizedMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let normalized = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maxResponseMessageLength))
    }

    /**
     Извлекает Retry-After как секунды или HTTP-date.
     - Parameter response: HTTP-ответ с заголовками retry.
     - Returns: Задержка перед повторной попыткой в секундах или nil.
     */
    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        let value = response.allHeaderFields.first { key, _ in
            (key as? String)?.caseInsensitiveCompare("Retry-After") == .orderedSame
        }?.value
        guard let value else { return nil }
        if let seconds = TimeInterval(String(describing: value)) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        guard let date = formatter.date(from: String(describing: value)) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}
