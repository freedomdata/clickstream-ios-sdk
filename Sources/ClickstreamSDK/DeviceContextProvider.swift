import Foundation
import CoreTelephony

/**
 Собирает параметры устройства и окружения для контекста событий.
 */
internal final class DeviceContextProvider {

    private let trackingOptionsProvider: () -> TrackingOptions
    private let networkMonitor: NetworkMonitor
    private let sdkVersion: String

    /**
     Создает провайдер контекста устройства.
     - Parameters:
       - trackingOptionsProvider: Замыкание для получения текущих настроек трекинга.
       - networkMonitor: Объект для получения текущего типа сети.
       - sdkVersion: Версия SDK для параметров контекста.
     */
    init(
        trackingOptionsProvider: @escaping () -> TrackingOptions,
        networkMonitor: NetworkMonitor,
        sdkVersion: String
    ) {
        self.trackingOptionsProvider = trackingOptionsProvider
        self.networkMonitor = networkMonitor
        self.sdkVersion = sdkVersion
    }

    /**
     Возвращает параметры устройства с учетом текущих настроек трекинга.
     - Returns: Словарь параметров устройства и окружения.
     */
    func getParams() -> [String: Any?] {
        let options = trackingOptionsProvider()
        if !options.isEnabled(.deviceContext) {
            return [:]
        }
        var result: [String: Any?] = [:]
        let pairs: [(StandardParam, () -> Any?)] = [
            (.appVersion, { [weak self] in self?.getAppVersion() }),
            (.osName, { "iOS" }),
            (.osVersion, { self.getOsVersion() }),
            (.locale, { self.getLocale() }),
            (.deviceModel, { self.getDeviceModel() }),
            (.carrier, { self.getCarrier() }),
            (.timezone, { self.getTimezoneOffset() }),
            (.networkType, { [weak self] in self?.networkMonitor.getNetworkType() }),
            (.sdkVersion, { [weak self] in self?.sdkVersion }),
        ]
        for (param, supplier) in pairs {
            guard options.isEnabled(param) else { continue }
            let value: Any? = supplier()
            result[param.rawValue] = value
        }
        return result
    }

    /**
     Возвращает версию приложения из основного bundle.
     - Returns: Версия приложения или nil.
     */
    private func getAppVersion() -> String? {
        guard let info = Bundle.main.infoDictionary else { return nil }
        if let short = info["CFBundleShortVersionString"] as? String, !short.isEmpty {
            return short
        }
        if let build = info["CFBundleVersion"] as? String, !build.isEmpty {
            return build
        }
        return nil
    }

    /**
     Возвращает версию операционной системы.
     - Returns: Версия iOS или nil.
     */
    private func getOsVersion() -> String? {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.patchVersion == 0 {
            return "\(v.majorVersion).\(v.minorVersion)"
        }
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /**
     Возвращает текущую локаль устройства.
     - Returns: Идентификатор текущей локали.
     */
    private func getLocale() -> String? {
        Locale.current.identifier
    }

    /**
     Возвращает модель устройства.
     - Returns: Название модели устройства или nil.
     */
    private func getDeviceModel() -> String? {
        var name = utsname()
        guard uname(&name) == 0 else { return nil }
        let machine = withUnsafePointer(to: &name.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        let normalized = machine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "unknown" else { return nil }

        let family: String? = {
            if normalized.hasPrefix("iPhone") { return "iPhone" }
            if normalized.hasPrefix("iPad") { return "iPad" }
            if normalized.hasPrefix("iPod") { return "iPod" }
            if normalized.hasPrefix("AppleTV") { return "Apple TV" }
            if normalized.hasPrefix("Watch") { return "Apple Watch" }
            return nil
        }()

        if let family {
            return "\(family) (\(normalized))"
        }
        return normalized
    }

    /**
     Возвращает название оператора сотовой связи.
     - Returns: Название оператора или nil.
     */
    private func getCarrier() -> String? {
        let info = CTTelephonyNetworkInfo()
        guard let providers = info.serviceSubscriberCellularProviders else { return nil }
        guard let name = providers.values.compactMap(\.carrierName).first else { return nil }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.lowercased() != "unknown", n != "--" else { return nil }
        return n
    }

    /**
     Возвращает смещение текущего часового пояса.
     - Returns: Строка со смещением часового пояса или nil.
     */
    private func getTimezoneOffset() -> String? {
        TimeUtils.tzOffsetString(for: TimeZone.current, at: Date())
    }
}