import Foundation

/**
 Отправляет события в Clickstream API.
 */
internal final class EventApiClient {

    /**
     Описывает результат отправки события для очереди.
     */
    enum QueueSendResult: Sendable {
        case success
        case retryableFailure
        case nonRetryableFailure
    }

    /**
     Ограничивает выполнение completion одним вызовом.
     */
    private final class CompletionGate: Sendable {
        private let lock = NSLock()
        private nonisolated(unsafe) var claimed = false

        /**
         Проверяет и фиксирует первый вызов completion.
         - Returns: Флаг успешной фиксации первого вызова.
         */
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }

    private let baseUrl: String
    private let apiKey: String
    private let session: URLSession
    private let requestTimeout: TimeInterval

    /**
     Создает клиент для отправки событий в Clickstream API.
     - Parameters:
       - baseUrl: Базовый URL сервера Clickstream.
       - apiKey: Ключ авторизации для доступа к API.
       - requestTimeout: Таймаут отправки запроса в секундах.
     */
    init(baseUrl: String, apiKey: String, requestTimeout: TimeInterval = 60) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.requestTimeout = requestTimeout

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout + 30
        configuration.timeoutIntervalForResource = requestTimeout + 30
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /**
     Отправляет событие в Clickstream API.
     - Parameters:
       - payload: Данные события для отправки.
       - completion: Замыкание с результатом отправки события.
     */
    func sendEvent(_ payload: [String: Any], completion: (@Sendable (QueueSendResult) -> Void)? = nil) {
        guard let url = ClickstreamURLBuilder.eventEndpointURL(baseUrl: baseUrl) else {
            ClickstreamLogger.log("Invalid URL: \(ClickstreamURLBuilder.eventEndpointDescription(baseUrl: baseUrl))")
            completion?(.nonRetryableFailure)
            return
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            ClickstreamLogger.log("Failed to serialize event payload.")
            completion?(.nonRetryableFailure)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout + 30
        request.httpBody = jsonData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let gate = CompletionGate()
        let deadline = Date().addingTimeInterval(requestTimeout)

        let task = session.dataTask(with: request) { _, response, error in
            guard gate.claim() else { return }

            if Date() >= deadline {
                ClickstreamLogger.log("Failed to send event: request timed out")
                completion?(.retryableFailure)
                return
            }

            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    ClickstreamLogger.log("Failed to send event: request timed out")
                case .notConnectedToInternet, .networkConnectionLost:
                    ClickstreamLogger.log("Failed to send event: network unavailable")
                case .cancelled:
                    ClickstreamLogger.log("Failed to send event: request cancelled")
                default:
                    ClickstreamLogger.log("Failed to send event: network error (\(urlError.code.rawValue))")
                }
                completion?(.retryableFailure)
                return
            }

            if let error = error {
                let nsError = error as NSError
                ClickstreamLogger.log("Failed to send event: error code (\(nsError.code))")
                completion?(.retryableFailure)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                ClickstreamLogger.log("Event send failed: invalid server response.")
                completion?(.retryableFailure)
                return
            }

            let code = httpResponse.statusCode
            if (200..<300).contains(code) {
                completion?(.success)
            } else if code == 429 || (500..<600).contains(code) {
                ClickstreamLogger.log("Event send failed. HTTP status: \(code) (retryable)")
                completion?(.retryableFailure)
            } else if (400..<500).contains(code) {
                ClickstreamLogger.log("Event send failed. HTTP status: \(code) (non-retryable)")
                completion?(.nonRetryableFailure)
            } else {
                ClickstreamLogger.log("Event send failed. HTTP status: \(code) (retryable)")
                completion?(.retryableFailure)
            }
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requestTimeout) {
            guard gate.claim() else {
                task.cancel()
                return
            }
            task.cancel()
            ClickstreamLogger.log("Failed to send event: request timed out")
            completion?(.retryableFailure)
        }

        task.resume()
    }
}