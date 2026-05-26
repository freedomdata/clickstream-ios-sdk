import Foundation

/**
 Основная точка входа для работы с Clickstream SDK.
 */
public final class ClickstreamSDK {

    nonisolated(unsafe) static let shared = ClickstreamSDK()

    /**
     Создает singleton-экземпляр Clickstream SDK.
     */
    private init() {}

    private let queue = DispatchQueue(label: "com.clickstream.sdk.state", qos: .utility)

    private var _config: ClickstreamConfig?
    private var _userId: String?
    private let deviceId: String = DeviceIdProvider().getDeviceId()
    private var _apiClient: EventApiClient?
    private var _eventQueue: EventQueue?
    private var _networkMonitor: NetworkMonitor?
    private var _sessionManager: SessionManager?
    private var _lifecycleObserver: AppLifecycleObserver?
    private var _autoTracker: AutoTracker?
    private var _autoTrackingEnabled: Bool = true
    private var _deviceContextProvider: DeviceContextProvider?
    private var _trackingOptions: TrackingOptions = TrackingOptions()
    private var _userCustomProfileParams: [String: Any] = [:]

    /**
     Инициализирует Clickstream SDK с переданной конфигурацией.
     - Parameters:
       - config: Конфигурация Clickstream SDK.
     */
    public static func initialize(config: ClickstreamConfig) {
        shared.initialize(config: config)
    }

    /**
     Регистрирует пользовательское событие.
     - Parameters:
       - eventName: Имя события.
       - props: Дополнительные параметры события.
     */
    public static func trackEvent(_ eventName: String, props: [String: Any] = [:]) {
        shared.trackEvent(eventName, props: props)
    }

    /**
     Устанавливает идентификатор пользователя для последующих событий.
     - Parameters:
       - userId: Идентификатор пользователя.
     */
    public static func setUserId(_ userId: String?) {
        shared.setUserId(userId)
    }

    /**
     Сбрасывает текущий идентификатор пользователя.
     */
    public static func clearUserId() {
        shared.clearUserId()
    }

    /**
     Включает или выключает автоматический сбор стандартных событий.
     - Parameters:
       - enabled: Флаг включения автотрекинга.
     */
    public static func setAutoTrackingEnabled(_ enabled: Bool) {
        shared.setAutoTrackingEnabled(enabled)
    }

    /**
     Возвращает текущее состояние автоматического сбора событий.
     - Returns: Флаг включения автотрекинга.
     */
    public static func isAutoTrackingEnabled() -> Bool {
        shared.isAutoTrackingEnabled()
    }

    /**
     Сообщает SDK об открытии приложения по deep link.
     - Parameters:
       - url: Строковое значение deep link.
     */
    public static func reportDeeplinkOpen(_ url: String) {
        shared.reportDeeplinkOpen(url)
    }

    /**
     Сообщает SDK об открытии приложения по URL deep link.
     - Parameters:
       - url: URL открытого deep link.
     */
    public static func reportDeeplinkOpen(_ url: URL) {
        reportDeeplinkOpen(url.absoluteString)
    }

    /**
     Сообщает SDK о ручном показе экрана.
     - Parameters:
       - screenName: Название показанного экрана.
     */
    public static func reportScreenView(_ screenName: String) {
        shared.reportScreenView(screenName: screenName)
    }

    /**
     Принудительно отправляет все накопленные события.
     */
    public static func flush() {
        shared.flushQueue()
    }

    /**
     Обновляет настройки сбора стандартных параметров.
     - Parameters:
       - options: Новые настройки сбора стандартных параметров.
     */
    public static func setTrackingOptions(_ options: TrackingOptions) {
        shared.setTrackingOptions(options)
    }

    /**
     Устанавливает пользовательские свойства профиля и отправляет событие user_properties.
     - Parameters:
       - properties: Пользовательские свойства профиля.
     */
    public static func setUserProperties(_ properties: [String: Any]) {
        shared.setUserProperties(properties)
    }

    /**
     Инициализирует внутренние компоненты SDK.
     - Parameters:
       - config: Конфигурация Clickstream SDK.
     */
    private func initialize(config: ClickstreamConfig) {
        let normalizedConfig = normalizeConfig(config)
        var didInitialize = false
        var sessionManagerToRecover: SessionManager?

        queue.sync {
            guard _config == nil else {
                ClickstreamLogger.log("The ClickstreamSDK has already been initialized")
                return
            }

            _config = normalizedConfig
            let apiClient = EventApiClient(baseUrl: normalizedConfig.baseUrl, apiKey: normalizedConfig.apiKey)
            _apiClient = apiClient
            _trackingOptions = normalizedConfig.trackingOptions

            NetworkMonitor.setDebounceMs(normalizedConfig.networkDebounceMs)

            let eventQueue = EventQueue(
                apiClient: apiClient,
                maxQueueSize: normalizedConfig.maxQueueSize,
                flushQueueSize: normalizedConfig.flushQueueSize,
                flushMaxRetries: normalizedConfig.flushMaxRetries,
                flushBatchSize: normalizedConfig.flushBatchSize,
                flushIntervalMillis: normalizedConfig.flushIntervalMillis,
                maxFlushProcessingTimeMs: normalizedConfig.maxFlushProcessingTimeMs
            )
            _eventQueue = eventQueue

            let networkMonitor = NetworkMonitor()
            _networkMonitor = networkMonitor

            NetworkMonitor.setOnConnectivityRestored { [weak eventQueue] in
                eventQueue?.flush()
            }

            let deviceContextProvider = DeviceContextProvider(
                trackingOptionsProvider: { [weak self] in
                    guard let self = self else { return TrackingOptions() }
                    return self.queue.sync { self._trackingOptions }
                },
                networkMonitor: networkMonitor,
                sdkVersion: normalizedConfig.sdkVersion
            )
            _deviceContextProvider = deviceContextProvider

            let storage = SessionStorage()
            let sessionManager = SessionManager(
                sessionTimeoutMs: normalizedConfig.sessionTimeoutMs,
                storage: storage,
                eventSender: { [weak self] eventName, payload in
                    self?.trackInternal(eventName, props: payload, includeDeviceContext: eventName == "session_start")
                },
                criticalEventSender: { [weak self] eventName, payload, completion in
                    self?.trackCriticalEvent(eventName, props: payload, completion: completion) ?? completion(false)
                }
            )
            _sessionManager = sessionManager

            let autoTracker = AutoTracker(eventSender: { [weak self] eventName, payload in
                self?.trackEvent(eventName, props: payload)
            })
            _autoTracker = autoTracker
            _autoTrackingEnabled = normalizedConfig.autoTrackingEnabled

            let lifecycleObserver = AppLifecycleObserver(sessionManager: sessionManager, autoTracker: autoTracker)
            lifecycleObserver.subscribe()
            _lifecycleObserver = lifecycleObserver

            applyAutoTracking(enabled: normalizedConfig.autoTrackingEnabled)

            didInitialize = true
            sessionManagerToRecover = sessionManager
        }

        guard didInitialize else { return }

        ClickstreamLogger.log("ClickstreamSDK initialized successfully")

        sessionManagerToRecover?.clearPendingAppClose()
        sessionManagerToRecover?.recoverSessionIfNeeded()
    }

    /**
     Возвращает конфигурацию с нормализованным baseUrl.
     - Parameters:
       - config: Исходная конфигурация Clickstream SDK.
     - Returns: Нормализованная конфигурация Clickstream SDK.
     */
    private func normalizeConfig(_ config: ClickstreamConfig) -> ClickstreamConfig {
        let normalizedBaseUrl = validateBaseUrl(config.baseUrl)
        return ClickstreamConfig(
            apiKey: config.apiKey,
            baseUrl: normalizedBaseUrl,
            sessionTimeoutMs: config.sessionTimeoutMs,
            autoTrackingEnabled: config.autoTrackingEnabled,
            trackingOptions: config.trackingOptions,
            sdkVersion: config.sdkVersion,
            flushQueueSize: config.flushQueueSize,
            flushMaxRetries: config.flushMaxRetries,
            maxQueueSize: config.maxQueueSize,
            flushIntervalMillis: config.flushIntervalMillis,
            flushBatchSize: config.flushBatchSize,
            maxFlushProcessingTimeMs: config.maxFlushProcessingTimeMs,
            networkDebounceMs: config.networkDebounceMs
        )
    }

    /**
     Проверяет baseUrl и возвращает значение без пробелов по краям.
     - Parameters:
       - baseUrl: Исходный базовый URL Clickstream backend.
     - Returns: Нормализованный базовый URL Clickstream backend.
     */
    private func validateBaseUrl(_ baseUrl: String) -> String {
        let normalizedBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: normalizedBaseUrl)
        let isHttps = url?.scheme?.lowercased() == "https"
        let errorMessage =
            "Insecure ClickstreamSDK configuration: baseUrl must use HTTPS. " +
            "Using HTTP may expose apiKey during transmission."

        if !isHttps {
            ClickstreamLogger.log(errorMessage)
        }

        precondition(isHttps, errorMessage)
        return normalizedBaseUrl
    }

    /**
     Регистрирует пользовательское событие через внутренний экземпляр SDK.
     - Parameters:
       - eventName: Имя события.
       - props: Дополнительные параметры события.
     */
    private func trackEvent(_ eventName: String, props: [String: Any]) {
        let snapshot: (EventApiClient?, String?, String, SessionManager?, TrackingOptions?, DeviceContextProvider?) = queue.sync {
            guard _apiClient != nil else { return (nil, _userId, deviceId, _sessionManager, _trackingOptions, _deviceContextProvider) }
            return (_apiClient, _userId, deviceId, _sessionManager, _trackingOptions, _deviceContextProvider)
        }

        guard let apiClient = snapshot.0 else {
            ClickstreamLogger.log("ClickstreamSDK is not initialized. First, call initialize().")
            return
        }

        snapshot.3?.ensureSession()

        trackInternal(
            eventName,
            props: props,
            includeDeviceContext: false,
            userPropertiesCustom: nil,
            apiClient: apiClient,
            userIdSnapshot: snapshot.1,
            deviceIdSnapshot: snapshot.2,
            sessionIdSnapshot: snapshot.3?.getSessionId(),
            trackingOptions: snapshot.4 ?? TrackingOptions(),
            deviceContextProvider: snapshot.5
        )
    }

    /**
     Отправляет событие с текущими внутренними параметрами SDK.
     - Parameters:
       - eventName: Имя события.
       - props: Дополнительные параметры события.
       - includeDeviceContext: Флаг добавления контекста устройства.
       - userPropertiesCustom: Пользовательские свойства профиля.
     */
    private func trackInternal(_ eventName: String, props: [String: Any], includeDeviceContext: Bool = false, userPropertiesCustom: [String: Any]? = nil) {
        let snapshot: (EventApiClient?, String?, String, String?, TrackingOptions?, DeviceContextProvider?) = queue.sync {
            (
                _apiClient,
                _userId,
                deviceId,
                _sessionManager?.getSessionId(),
                _trackingOptions,
                _deviceContextProvider
            )
        }

        guard let apiClient = snapshot.0 else { return }

        let sessionId = snapshot.3 ?? queue.sync { _sessionManager?.getSessionId() }

        trackInternal(
            eventName,
            props: props,
            includeDeviceContext: includeDeviceContext,
            userPropertiesCustom: userPropertiesCustom,
            apiClient: apiClient,
            userIdSnapshot: snapshot.1,
            deviceIdSnapshot: snapshot.2,
            sessionIdSnapshot: sessionId,
            trackingOptions: snapshot.4 ?? TrackingOptions(),
            deviceContextProvider: snapshot.5
        )
    }

    /**
     Отправляет событие с переданным снимком состояния SDK.
     - Parameters:
       - eventName: Имя события.
       - props: Дополнительные параметры события.
       - includeDeviceContext: Флаг добавления контекста устройства.
       - userPropertiesCustom: Пользовательские свойства профиля.
       - apiClient: Клиент для отправки события.
       - userIdSnapshot: Снимок идентификатора пользователя.
       - deviceIdSnapshot: Снимок идентификатора устройства.
       - sessionIdSnapshot: Снимок идентификатора сессии.
       - trackingOptions: Настройки сбора стандартных параметров.
       - deviceContextProvider: Провайдер контекста устройства.
     */
    private func trackInternal(
        _ eventName: String,
        props: [String: Any],
        includeDeviceContext: Bool,
        userPropertiesCustom: [String: Any]?,
        apiClient: EventApiClient,
        userIdSnapshot: String?,
        deviceIdSnapshot: String,
        sessionIdSnapshot: String?,
        trackingOptions: TrackingOptions,
        deviceContextProvider: DeviceContextProvider?
    ) {
        guard let payload = buildEventPayload(
            eventName: eventName,
            props: props,
            includeDeviceContext: includeDeviceContext,
            userPropertiesCustom: userPropertiesCustom,
            userIdSnapshot: userIdSnapshot,
            deviceIdSnapshot: deviceIdSnapshot,
            sessionIdSnapshot: sessionIdSnapshot,
            trackingOptions: trackingOptions,
            deviceContextProvider: deviceContextProvider
        ) else {
            return
        }

        let eq: EventQueue? = self.queue.sync { self._eventQueue }

        if let eq {
            eq.enqueue(payload)
        } else {
            apiClient.sendEvent(payload)
        }
    }

    /**
     Отправляет критическое событие напрямую через API-клиент.
     - Parameters:
       - eventName: Имя события.
       - props: Дополнительные параметры события.
       - completion: Замыкание с результатом отправки.
     */
    private func trackCriticalEvent(
        _ eventName: String,
        props: [String: Any],
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let snapshot: (EventApiClient?, String?, String, TrackingOptions?, DeviceContextProvider?) = queue.sync {
            (
                _apiClient,
                _userId,
                deviceId,
                _trackingOptions,
                _deviceContextProvider
            )
        }

        guard let apiClient = snapshot.0 else {
            ClickstreamLogger.log("ClickstreamSDK is not initialized. First, call initialize().")
            completion(false)
            return
        }

        guard let payload = buildEventPayload(
            eventName: eventName,
            props: props,
            includeDeviceContext: false,
            userPropertiesCustom: nil,
            userIdSnapshot: snapshot.1,
            deviceIdSnapshot: snapshot.2,
            sessionIdSnapshot: props["sessionId"] as? String,
            trackingOptions: snapshot.3 ?? TrackingOptions(),
            deviceContextProvider: snapshot.4
        ) else {
            completion(false)
            return
        }

        apiClient.sendEvent(payload) { result in
            completion(result == .success)
        }
    }

    /**
     Формирует payload события с системными и пользовательскими параметрами.
     - Parameters:
       - eventName: Имя события.
       - props: Дополнительные параметры события.
       - includeDeviceContext: Флаг добавления контекста устройства.
       - userPropertiesCustom: Пользовательские свойства профиля.
       - userIdSnapshot: Снимок идентификатора пользователя.
       - deviceIdSnapshot: Снимок идентификатора устройства.
       - sessionIdSnapshot: Снимок идентификатора сессии.
       - trackingOptions: Настройки сбора стандартных параметров.
       - deviceContextProvider: Провайдер контекста устройства.
     - Returns: Payload события или nil при ошибке сериализации.
     */
    private func buildEventPayload(
        eventName: String,
        props: [String: Any],
        includeDeviceContext: Bool,
        userPropertiesCustom: [String: Any]?,
        userIdSnapshot: String?,
        deviceIdSnapshot: String,
        sessionIdSnapshot: String?,
        trackingOptions: TrackingOptions,
        deviceContextProvider: DeviceContextProvider?
    ) -> [String: Any]? {
        var payload: [String: Any] = [:]
        payload.merge(props) { _, new in new }

        if trackingOptions.isEnabled(.eventName) {
            payload["eventName"] = eventName
        }
        if trackingOptions.isEnabled(.eventDate), payload["eventDate"] == nil {
            payload["eventDate"] = TimeUtils.nowWithOffset()
        }
        if trackingOptions.isEnabled(.deviceId) {
            payload["deviceId"] = deviceIdSnapshot
        }
        if trackingOptions.isEnabled(.sessionId), payload["sessionId"] == nil, let sessionId = sessionIdSnapshot {
            payload["sessionId"] = sessionId
        }
        if trackingOptions.isEnabled(.userId), let userId = userIdSnapshot {
            payload["clientId"] = userId
        }

        if let custom = userPropertiesCustom {
            if let provider = deviceContextProvider {
                let sdkParams = provider.getParams()
                let merged = UserPropertiesContextMerger.merge(custom: custom, sdkParams: sdkParams)
                if !merged.isEmpty {
                    payload["context"] = merged
                }
            } else if !custom.isEmpty {
                payload["context"] = custom
            }
        } else if includeDeviceContext, trackingOptions.isEnabled(.deviceContext), let provider = deviceContextProvider {
            let contextParams = provider.getParams()
            if !contextParams.isEmpty {
                payload["context"] = contextParams.mapValues { $0 ?? NSNull() }
            }
        }

        guard (try? JSONSerialization.data(
            withJSONObject: payload,
            options: JSONSerialization.WritingOptions([.prettyPrinted, .sortedKeys])
        )) != nil else {
            ClickstreamLogger.log("Failed to serialize event payload.")
            return nil
        }

        return payload
    }

    /**
     Устанавливает идентификатор пользователя во внутреннем состоянии SDK.
     - Parameters:
       - userId: Идентификатор пользователя.
     */
    private func setUserId(_ userId: String?) {
        let didSet = queue.sync { () -> Bool in
            guard _config != nil else {
                ClickstreamLogger.log("ClickstreamSDK is not initialized. Call initialize() before setUserId().")
                return false
            }

            if let userId = userId, userId.trimmingCharacters(in: .whitespaces).isEmpty {
                ClickstreamLogger.log("setUserId was called with empty or blank value. userId will be cleared.")
            }

            _userId = userId
            return true
        }

        if didSet { ClickstreamLogger.log("UserId successfully set") }
    }

    /**
     Сбрасывает идентификатор пользователя во внутреннем состоянии SDK.
     */
    private func clearUserId() {
        queue.sync {
            _userId = nil
        }
    }

    /**
     Сохраняет пользовательские свойства профиля и отправляет событие user_properties.
     - Parameters:
       - properties: Пользовательские свойства профиля.
     */
    private func setUserProperties(_ properties: [String: Any]) {
        let prepared: (
            apiClient: EventApiClient,
            userId: String?,
            deviceId: String,
            sessionManager: SessionManager?,
            trackingOptions: TrackingOptions,
            deviceContext: DeviceContextProvider?,
            customSnapshot: [String: Any]
        )? = queue.sync {
            guard let apiClient = _apiClient else {
                ClickstreamLogger.log("ClickstreamSDK is not initialized. Call initialize() before setUserProperties().")
                return nil
            }

            for (key, value) in properties {
                _userCustomProfileParams[key] = value
            }

            let customSnapshot = _userCustomProfileParams

            return (
                apiClient,
                _userId,
                deviceId,
                _sessionManager,
                _trackingOptions,
                _deviceContextProvider,
                customSnapshot
            )
        }

        guard let p = prepared else { return }

        p.sessionManager?.ensureSession()

        trackInternal(
            "user_properties",
            props: [:],
            includeDeviceContext: false,
            userPropertiesCustom: p.customSnapshot,
            apiClient: p.apiClient,
            userIdSnapshot: p.userId,
            deviceIdSnapshot: p.deviceId,
            sessionIdSnapshot: p.sessionManager?.getSessionId(),
            trackingOptions: p.trackingOptions,
            deviceContextProvider: p.deviceContext
        )
    }

    /**
     Обновляет состояние автотрекинга во внутреннем состоянии SDK.
     - Parameters:
       - enabled: Флаг включения автотрекинга.
     */
    private func setAutoTrackingEnabled(_ enabled: Bool) {
        queue.sync {
            guard _config != nil else {
                ClickstreamLogger.log("ClickstreamSDK is not initialized. Call initialize() first.")
                return
            }

            _autoTrackingEnabled = enabled
        }

        applyAutoTracking(enabled: enabled)
    }

    /**
     Возвращает состояние автотрекинга во внутреннем состоянии SDK.
     - Returns: Флаг включения автотрекинга.
     */
    private func isAutoTrackingEnabled() -> Bool {
        queue.sync { _config != nil && _autoTrackingEnabled }
    }

    /**
     Применяет состояние автотрекинга к AutoTracker и ScreenTracking.
     - Parameters:
       - enabled: Флаг включения автотрекинга.
     */
    private func applyAutoTracking(enabled: Bool) {
        if enabled {
            _autoTracker?.enable()
            ScreenTracking.setOnScreenAppear { [weak self] screenName in
                self?.reportScreenView(screenName: screenName)
            }
        } else {
            _autoTracker?.disable()
            ScreenTracking.setOnScreenAppear(nil)
        }
    }

    /**
     Обрабатывает ручной отчет о показе экрана.
     - Parameters:
       - screenName: Название показанного экрана.
     */
    internal func reportScreenView(screenName: String) {
        guard isAutoTrackingEnabled() else { return }

        if screenName.contains("PresentationHostingController") {
            return
        }

        let readableName = normalizeScreenName(screenName)

        if readableName == "RootView" {
            return
        }

        _autoTracker?.onScreenResumed(screenName: readableName)
    }

    /**
     Возвращает читаемое имя экрана без технических суффиксов.
     - Parameters:
       - name: Исходное имя экрана.
     - Returns: Нормализованное имя экрана.
     */
    private func normalizeScreenName(_ name: String) -> String {
        var result = name

        if result.hasPrefix("UIHostingController<"), result.hasSuffix(">") {
            let start = result.index(result.startIndex, offsetBy: "UIHostingController<".count)
            let end = result.index(result.endIndex, offsetBy: -1)
            let inner = String(result[start..<end])
            result = extractSwiftUIScreenName(from: inner) ?? inner
        }

        if result.hasSuffix("ViewController") {
            result = String(result.dropLast("ViewController".count))
        }

        return result.isEmpty ? name : result
    }

    /**
     Извлекает имя SwiftUI-экрана из имени hosting controller.
     - Parameters:
       - hostingControllerInner: Внутреннее имя типа из UIHostingController.
     - Returns: Имя SwiftUI-экрана или nil.
     */
    private func extractSwiftUIScreenName(from hostingControllerInner: String) -> String? {
        let s = hostingControllerInner

        let pattern = #"(?:^|[<,\s\(])([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(?=[>,\s\)])"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }

        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))

        if matches.isEmpty { return nil }

        let wrappers: Set<String> = [
            "AnyView",
            "ModifiedContent",
            "TupleView",
            "Optional",
            "Group",
            "ForEach",
            "VStack",
            "HStack",
            "ZStack",
            "ScrollView",
            "List",
            "NavigationStack",
            "NavigationView",
            "EmptyView",
            "Text"
        ]

        var best: (score: Int, name: String)?

        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }

            let raw = ns.substring(with: m.range(at: 1))
            let short = raw.split(separator: ".").last.map(String.init) ?? raw

            if short.isEmpty { continue }
            if short.hasPrefix("_") { continue }
            if short == "RootView" { continue }
            if short.hasSuffix("Modifier") { continue }
            if wrappers.contains(short) { continue }

            let score: Int
            if short.hasSuffix("View") || short.hasSuffix("Screen") || short.localizedCaseInsensitiveContains("Screen") {
                score = 3
            } else {
                score = 1
            }

            if let current = best {
                if score > current.score {
                    best = (score, short)
                } else if score == current.score {
                    best = (score, short)
                }
            } else {
                best = (score, short)
            }
        }

        return best?.name
    }

    /**
     Передает информацию об открытии deep link в автотрекер.
     - Parameters:
       - url: Строковое значение deep link.
     */
    private func reportDeeplinkOpen(_ url: String) {
        _autoTracker?.reportDeeplinkOpen(url: url)
    }

    /**
     Запускает отправку накопленных событий из очереди.
     */
    private func flushQueue() {
        let eq: EventQueue? = queue.sync { _eventQueue }

        guard let eq else {
            ClickstreamLogger.log("ClickstreamSDK is not initialized. Call initialize() before flush().")
            return
        }

        eq.flush()
    }

    /**
     Обновляет настройки сбора стандартных параметров во внутреннем состоянии SDK.
     - Parameters:
       - options: Новые настройки сбора стандартных параметров.
     */
    private func setTrackingOptions(_ options: TrackingOptions) {
        let applied = queue.sync { () -> Bool in
            guard _config != nil else { return false }
            _trackingOptions = options
            return true
        }

        if !applied {
            ClickstreamLogger.log("ClickstreamSDK is not initialized. Call initialize() first.")
            return
        }

        ClickstreamLogger.log("TrackingOptions updated: disabled=\(options.disabledFields)")
    }
}