import Foundation

/**
 Управляет автоматической отправкой стандартных событий SDK.
 */
internal final class AutoTracker {

    private static let screenViewThrottleMs: TimeInterval = 2_000

    private let eventSender: (String, [String: Any]) -> Void
    private let queue = DispatchQueue(label: "com.clickstream.sdk.autotrack", qos: .utility)

    private var _enabled = false
    private var _currentScreen: String?
    private var _previousScreen: String?
    private var _lastScreenViewTime: TimeInterval = 0
    private var _skipNextScreenView = false
    private var _firstForegroundHandled = false

    /**
     Создает автотрекер с обработчиком отправки событий.
     - Parameters:
       - eventSender: Замыкание для отправки имени события и его параметров.
     */
    init(eventSender: @escaping (String, [String: Any]) -> Void) {
        self.eventSender = eventSender
    }

    /**
     Включает автоматическую отправку стандартных событий.
     */
    func enable() {
        queue.sync {
            guard !_enabled else { return }
            _enabled = true
            ClickstreamLogger.log("Auto-tracking of standard events ENABLED")
        }
    }

    /**
     Отключает автоматическую отправку событий и сбрасывает внутреннее состояние.
     */
    func disable() {
        queue.sync {
            guard _enabled else { return }
            _enabled = false
            _currentScreen = nil
            _previousScreen = nil
            _lastScreenViewTime = 0
            _skipNextScreenView = false
            _firstForegroundHandled = false
            ClickstreamLogger.log("Auto-tracking of standard events DISABLED")
        }
    }

    /**
     Проверяет, включена ли автоматическая отправка стандартных событий.
     - Returns: Флаг включения автоматической отправки.
     */
    func isEnabled() -> Bool {
        queue.sync { _enabled }
    }

    /**
     Обрабатывает переход приложения в foreground и отправляет событие app_start.
     */
    func onAppForeground() {
        let shouldSend = queue.sync { () -> Bool in
            guard _enabled else { return false }
            if _firstForegroundHandled {
                _skipNextScreenView = true
            } else {
                _firstForegroundHandled = true
            }
            return true
        }
        if shouldSend {
            eventSender("app_start", [:])
        }
    }

    /**
     Обрабатывает переход приложения в background и отправляет событие app_close.
     - Parameters:
       - eventDate: Дата события, которую нужно передать в app_close.
     */
    func onAppBackground(eventDate: String? = nil) {
        let shouldSend = queue.sync { () -> Bool in
            guard _enabled else { return false }
            return true
        }
        if shouldSend {
            if let eventDate {
                eventSender("app_close", ["eventDate": eventDate])
            } else {
                eventSender("app_close", [:])
            }
        }
    }

    /**
     Обрабатывает показ экрана и отправляет событие screen_view с учетом throttle.
     - Parameters:
       - screenName: Название показанного экрана.
     */
    func onScreenResumed(screenName: String) {
        let shouldSend: (Bool, [String: Any])? = queue.sync { () -> (Bool, [String: Any])? in
            guard _enabled else { return nil }

            if _skipNextScreenView {
                _skipNextScreenView = false
                if let current = _currentScreen,
                   Self.logicalScreenName(screenName) == Self.logicalScreenName(current) {
                    _currentScreen = screenName
                    _lastScreenViewTime = Self.monotonicMs()
                    return nil
                }
            }

            let now = Self.monotonicMs()
            let screenDidChange = screenName != _currentScreen
            let throttleWindowExpired = now - _lastScreenViewTime >= Self.screenViewThrottleMs

            if screenDidChange {
                if let current = _currentScreen, Self.logicalScreenName(screenName) == Self.logicalScreenName(current) {
                    return nil
                }
                _previousScreen = _currentScreen
                _currentScreen = screenName
                _lastScreenViewTime = now
                return (true, buildScreenViewPayload(includePreviousScreen: true))
            }

            if throttleWindowExpired {
                _lastScreenViewTime = now
                return (true, buildScreenViewPayload(includePreviousScreen: false))
            }

            return nil
        }

        if let (_, payload) = shouldSend {
            eventSender("screen_view", payload)
        }
    }

    /**
     Формирует параметры события screen_view.
     - Parameters:
       - includePreviousScreen: Флаг добавления предыдущего экрана в параметры.
     - Returns: Параметры события screen_view.
     */
    private func buildScreenViewPayload(includePreviousScreen: Bool) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let s = _currentScreen { payload["screen"] = s }
        if includePreviousScreen, let s = _previousScreen { payload["previousScreen"] = s }
        return payload
    }

    /**
     Отправляет событие deeplink_open при открытии приложения по deep link.
     - Parameters:
       - url: Строковое значение открытого deep link.
     */
    func reportDeeplinkOpen(url: String) {
        let shouldSend: Bool = queue.sync { _enabled }
        if shouldSend {
            eventSender("deeplink_open", ["deeplink": url])
        }
    }

    /**
     Возвращает монотонное время работы процесса в миллисекундах.
     - Returns: Время работы процесса в миллисекундах.
     */
    private static func monotonicMs() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime * 1000
    }

    /**
     Возвращает логическое имя экрана без стандартных суффиксов.
     - Parameters:
       - name: Исходное имя экрана.
     - Returns: Нормализованное имя экрана.
     */
    private static func logicalScreenName(_ name: String) -> String {
        var s = name
        if s.hasSuffix("ViewController") { s = String(s.dropLast("ViewController".count)) }
        if s.hasSuffix("View") { s = String(s.dropLast("View".count)) }
        return s
    }
}