import Foundation

/**
 Хранит пути Clickstream API на общем gateway host.
 */
internal enum ClickstreamServicePath {
    static let event = "/api/click-stream-rest/event"
    static let eventSuffix = "/event"
    static let flags = "/api/click-stream-rest-flag/flag"
}

/**
 Собирает endpoint URL из `baseUrl` конфигурации SDK.
 Host всегда берется из `baseUrl`, пути сервисов фиксированы платформой.
 */
internal enum ClickstreamURLBuilder {

    /**
     Возвращает URL отправки событий.
     Для `baseUrl` без path использует платформенный путь event-сервиса.
     Для `baseUrl` с path сохраняет legacy-семантику: `baseUrl + /event`.
     */
    static func eventEndpointURL(baseUrl: String) -> URL? {
        if hasPathInBaseUrl(baseUrl) {
            return URL(string: "\(normalizedBase(baseUrl))\(ClickstreamServicePath.eventSuffix)")
        }
        return sameHostURL(baseUrl: baseUrl, absolutePath: ClickstreamServicePath.event)
    }

    /**
     Возвращает URL запроса флагов на том же host, что и `baseUrl`.
     */
    static func flagsEndpointURL(baseUrl: String, deviceId: String) -> URL? {
        return sameHostURL(
            baseUrl: baseUrl,
            absolutePath: ClickstreamServicePath.flags,
            queryItems: [URLQueryItem(name: "deviceId", value: deviceId)]
        )
    }

    /**
     Возвращает текстовое описание URL событий для логов об ошибке.
     */
    static func eventEndpointDescription(baseUrl: String) -> String {
        if hasPathInBaseUrl(baseUrl) {
            return "\(normalizedBase(baseUrl))\(ClickstreamServicePath.eventSuffix)"
        }
        return endpointDescription(baseUrl: baseUrl, absolutePath: ClickstreamServicePath.event)
    }

    /**
     Возвращает текстовое описание URL флагов для логов об ошибке.
     */
    static func flagsEndpointDescription(baseUrl: String, deviceId: String) -> String {
        flagsEndpointURL(baseUrl: baseUrl, deviceId: deviceId)?.absoluteString
            ?? "\(normalizedBase(baseUrl))\(ClickstreamServicePath.flags)?deviceId=\(deviceId)"
    }

    /**
     Собирает URL на том же host, что и `baseUrl`, с абсолютным path от корня gateway.
     */
    private static func sameHostURL(
        baseUrl: String,
        absolutePath: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        guard let baseURL = URL(string: normalizedBase(baseUrl)),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.path = absolutePath
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        components.fragment = nil
        return components.url
    }

    /**
     Возвращает текстовое описание endpoint URL для логов об ошибке.
     */
    private static func endpointDescription(baseUrl: String, absolutePath: String) -> String {
        guard let url = sameHostURL(baseUrl: baseUrl, absolutePath: absolutePath) else {
            return "\(normalizedBase(baseUrl))\(absolutePath)"
        }
        return url.absoluteString
    }

    /**
     Проверяет, содержит ли `baseUrl` path помимо host.
     */
    private static func hasPathInBaseUrl(_ baseUrl: String) -> Bool {
        guard let url = URL(string: normalizedBase(baseUrl)) else {
            return false
        }
        let path = url.path
        return !path.isEmpty && path != "/"
    }

    /**
     Убирает завершающий слеш у `baseUrl`.
     */
    private static func normalizedBase(_ baseUrl: String) -> String {
        baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
    }
}
