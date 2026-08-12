import Foundation
import Network

/**
 Отслеживает доступность сети и определяет ее тип.
 */
internal final class NetworkMonitor {

    private static let queue = DispatchQueue(label: "com.clickstream.sdk.network")
    private static let lock = NSLock()

    private nonisolated(unsafe) static var _networkType: String?
    private nonisolated(unsafe) static var _hasResolvedInitialPath = false

    private static let callbackLock = NSLock()
    private static let debounceLock = NSLock()
    private nonisolated(unsafe) static var _onConnectivityRestored: (() -> Void)?
    private nonisolated(unsafe) static var _lastConnectivityNotifyTime: CFAbsoluteTime?
    private nonisolated(unsafe) static var _debounceSeconds: TimeInterval = 0.5

    private var monitor: NWPathMonitor?

    /**
     Устанавливает debounce для уведомления о восстановлении сети.
     - Parameters:
       - ms: Интервал debounce в миллисекундах.
     */
    static func setDebounceMs(_ ms: TimeInterval) {
        debounceLock.lock()
        _debounceSeconds = max(0, ms / 1000.0)
        debounceLock.unlock()
    }

    /**
     Создает монитор сети и запускает отслеживание изменений.
     */
    init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { path in
            let wasOffline = NetworkMonitor.isOffline()
            NetworkMonitor.updateNetworkType(path: path)
            let isNowOnline = !NetworkMonitor.isOffline()
            if wasOffline && isNowOnline {
                NetworkMonitor.notifyConnectivityRestored()
            }
        }

        monitor.start(queue: NetworkMonitor.queue)
    }

    /**
     Устанавливает callback для события восстановления сети.
     - Parameters:
       - handler: Замыкание для вызова при восстановлении сети.
     */
    static func setOnConnectivityRestored(_ handler: (() -> Void)?) {
        callbackLock.lock()
        _onConnectivityRestored = handler
        callbackLock.unlock()
    }

    /**
     Проверяет, доступна ли сеть для отправки данных.
     - Returns: Флаг доступности сети.
     */
    static func isNetworkAvailable() -> Bool {
        !isOffline()
    }

    /**
     Уведомляет подписчика о восстановлении сети с учетом debounce.
     */
    private static func notifyConnectivityRestored() {
        let now = CFAbsoluteTimeGetCurrent()
        debounceLock.lock()
        let debounce = _debounceSeconds
        if let last = _lastConnectivityNotifyTime, now - last < debounce {
            debounceLock.unlock()
            return
        }
        _lastConnectivityNotifyTime = now
        debounceLock.unlock()

        callbackLock.lock()
        let handler = _onConnectivityRestored
        callbackLock.unlock()
        handler?()
    }

    /**
     Проверяет, находится ли сеть в состоянии offline.
     - Returns: Флаг отсутствия доступной сети.
     */
    private static func isOffline() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_hasResolvedInitialPath || _networkType == "none"
    }

    /**
     Обновляет сохраненный тип сети по текущему NWPath.
     - Parameters:
       - path: Текущее состояние сетевого пути.
     */
    private static func updateNetworkType(path: NWPath) {
        lock.lock()
        defer { lock.unlock() }

        _hasResolvedInitialPath = true

        if path.status != .satisfied {
            _networkType = "none"
            return
        }

        if path.usesInterfaceType(.wifi) {
            _networkType = "wifi"
        } else if path.usesInterfaceType(.cellular) {
            _networkType = "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            _networkType = "ethernet"
        } else {
            _networkType = "none"
        }
    }

    /**
     Возвращает текущий тип сети.
     - Returns: Тип сети или nil до первого определения состояния.
     */
    func getNetworkType() -> String? {
        NetworkMonitor.lock.lock()
        defer { NetworkMonitor.lock.unlock() }

        guard NetworkMonitor._hasResolvedInitialPath else {
            return nil
        }
        return NetworkMonitor._networkType
    }
}