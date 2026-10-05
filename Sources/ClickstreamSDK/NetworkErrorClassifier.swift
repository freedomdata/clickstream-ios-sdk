import Foundation

/**
 Классифицирует транспортные ошибки batch-запросов для retry.
 */
internal enum NetworkErrorClassifier {

    /**
     Возвращает true только для временных сетевых ошибок, допускающих повторную отправку.
     - Parameter error: Транспортная ошибка batch-запроса.
     - Returns: Флаг возможности повторной отправки.
     */
    static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable,
             .backgroundSessionWasDisconnected:
            return true
        default:
            return false
        }
    }
}
