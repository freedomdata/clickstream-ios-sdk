import Foundation

/**
 Контракт клиента для запроса конфигурации флагов.
 */
internal protocol FlagFetching: AnyObject {
    /**
     Запрашивает конфигурацию флагов для устройства.
     - Parameters:
       - deviceId: Идентификатор устройства.
       - completion: Замыкание с результатом запроса.
     */
    func fetchFlags(deviceId: String, completion: @escaping @Sendable (FlagApiClient.FetchResult) -> Void)
}

/**
 Запрашивает конфигурацию флагов из Clickstream Flag API.
 */
internal final class FlagApiClient: FlagFetching {

    /**
     Описывает результат HTTP-запроса флагов.
     */
    enum FetchResult: Sendable {
        case success([FlagInfo])
        case failure(FlagsFetchError)
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
     Создает клиент для запроса конфигурации флагов.
     - Parameters:
       - baseUrl: Базовый URL сервера Clickstream.
       - apiKey: Ключ авторизации для доступа к API.
       - requestTimeout: Таймаут запроса в секундах.
       - session: Пользовательская URLSession для тестов и кастомных конфигураций.
     */
    init(baseUrl: String, apiKey: String, requestTimeout: TimeInterval = 60, session: URLSession? = nil) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.requestTimeout = requestTimeout

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = requestTimeout + 30
            configuration.timeoutIntervalForResource = requestTimeout + 30
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    /**
     Запрашивает конфигурацию флагов для устройства.
     - Parameters:
       - deviceId: Идентификатор устройства.
       - completion: Замыкание с результатом запроса.
     */
    func fetchFlags(deviceId: String, completion: @escaping @Sendable (FetchResult) -> Void) {
        let invalidURLDescription = ClickstreamURLBuilder.flagsEndpointDescription(
            baseUrl: baseUrl,
            deviceId: deviceId
        )
        guard let url = ClickstreamURLBuilder.flagsEndpointURL(baseUrl: baseUrl, deviceId: deviceId) else {
            ClickstreamLogger.log("Invalid URL: \(invalidURLDescription)")
            completion(.failure(.invalidUrl))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout + 30
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        ClickstreamLogger.log("Fetching flags")

        let gate = CompletionGate()
        let deadline = Date().addingTimeInterval(requestTimeout)

        let task = session.dataTask(with: request) { data, response, error in
            guard gate.claim() else { return }

            if Date() >= deadline {
                ClickstreamLogger.log("Failed to fetch flags: request timed out")
                completion(.failure(.requestTimedOut))
                return
            }

            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    completion(.failure(.requestTimedOut))
                case .notConnectedToInternet, .networkConnectionLost:
                    completion(.failure(.networkUnavailable))
                default:
                    completion(.failure(.requestFailed))
                }
                ClickstreamLogger.log("Failed to fetch flags: network error (\(urlError.code.rawValue))")
                return
            }

            if error != nil {
                ClickstreamLogger.log("Failed to fetch flags: request failed")
                completion(.failure(.requestFailed))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                ClickstreamLogger.log("Failed to fetch flags: invalid server response")
                completion(.failure(.invalidResponse))
                return
            }

            let code = httpResponse.statusCode
            ClickstreamLogger.log("Flags fetch response: HTTP \(code)")

            guard (200..<300).contains(code) else {
                ClickstreamLogger.log("Failed to fetch flags. HTTP status: \(code)")
                completion(.failure(.httpError(code)))
                return
            }

            guard let data else {
                ClickstreamLogger.log("Failed to fetch flags: empty response body")
                completion(.failure(.invalidResponse))
                return
            }

            guard let flags = try? JSONDecoder().decode([FlagInfo].self, from: data) else {
                ClickstreamLogger.log("Failed to fetch flags: invalid response payload")
                completion(.failure(.invalidResponse))
                return
            }

            let flagNames = flags.compactMap(\.name).joined(separator: ", ")
            let namesSuffix = flagNames.isEmpty ? "" : ", names: [\(flagNames)]"
            ClickstreamLogger.log("Flags fetch succeeded: decoded \(flags.count) flag(s)\(namesSuffix)")

            completion(.success(flags))
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + requestTimeout) {
            guard gate.claim() else {
                return
            }
            task.cancel()
            ClickstreamLogger.log("Failed to fetch flags: request timed out")
            completion(.failure(.requestTimedOut))
        }

        task.resume()
    }
}
