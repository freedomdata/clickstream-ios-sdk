import Foundation
import UIKit

/**
 Наблюдает за изменениями жизненного цикла приложения.
 */
internal final class AppLifecycleObserver {

    private static let backgroundDelayMs: TimeInterval = 3.0
    private static let terminateSendTimeoutSec: TimeInterval = 2.0

    private let sessionManager: SessionManager
    private weak var autoTracker: AutoTracker?
    private var subscribed = false
    private var foreground = false
    private var paused = true
    private var checkBackgroundWorkItem: DispatchWorkItem?
    private var didSendAppCloseSinceLastForeground = false

    /**
     Создает наблюдатель жизненного цикла приложения с менеджером сессий и автотрекером.
     - Parameters:
       - sessionManager: Менеджер сессий приложения.
       - autoTracker: Автотрекер событий приложения.
     */
    init(sessionManager: SessionManager, autoTracker: AutoTracker? = nil) {
        self.sessionManager = sessionManager
        self.autoTracker = autoTracker
        syncWithCurrentStateIfPossible()
    }

    /**
     Подписывает наблюдатель на системные уведомления жизненного цикла приложения.
     */
    func subscribe() {
        guard !subscribed else { return }
        subscribed = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(onBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(onForeground), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(onInactive), name: UIApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(onTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    /**
     Отписывает наблюдатель от всех системных уведомлений.
     */
    func unsubscribe() {
        guard subscribed else { return }
        subscribed = false
        NotificationCenter.default.removeObserver(self)
    }

    /**
     Обрабатывает переход приложения в активное состояние.
     */
    @objc private func onForeground() {
        paused = false
        let wasBackground = !foreground
        foreground = true
        didSendAppCloseSinceLastForeground = false

        checkBackgroundWorkItem?.cancel()
        checkBackgroundWorkItem = nil

        sessionManager.clearPendingAppClose()

        if wasBackground {
            sessionManager.onForeground()
            autoTracker?.onAppForeground()
        }
    }

    /**
     Обрабатывает переход приложения в фоновое состояние.
     */
    @objc private func onBackground() {
        paused = true

        checkBackgroundWorkItem?.cancel()
        checkBackgroundWorkItem = nil

        if foreground {
            sessionManager.onBackground()
            autoTracker?.onAppBackground(eventDate: sessionManager.getLastBackgroundEventDate())
            didSendAppCloseSinceLastForeground = true
            sessionManager.clearPendingAppClose()
            foreground = false
            return
        }
    }

    /**
     Обрабатывает временный переход приложения в неактивное состояние.
     */
    @objc private func onInactive() {
        paused = true
    }

    /**
     Обрабатывает завершение работы приложения.
     */
    @MainActor
    @objc private func onTerminate() {
        let backgroundTask = TerminateBackgroundTask()
        backgroundTask.start()

        if !didSendAppCloseSinceLastForeground {
            autoTracker?.onAppBackground(eventDate: sessionManager.getLastBackgroundEventDate())
        }

        let semaphore = DispatchSemaphore(value: 0)
        sessionManager.onTerminate { _ in
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + Self.terminateSendTimeoutSec)

        backgroundTask.end()
    }

    /**
     Управляет background task при завершении приложения.
     */
    @MainActor
    private final class TerminateBackgroundTask {
        private var id: UIBackgroundTaskIdentifier = .invalid

        /**
         Запускает background task для завершения работы SDK.
         */
        func start() {
            id = UIApplication.shared.beginBackgroundTask(
                withName: "com.clickstream.sdk.terminate",
                expirationHandler: { self.end() }
            )
        }

        /**
         Завершает background task, если он активен.
         */
        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    /**
     Синхронизирует состояние наблюдателя с текущим состоянием приложения.
     */
    private func syncWithCurrentStateIfPossible() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let state = MainActor.assumeIsolated { UIApplication.shared.applicationState }
            switch state {
            case .active:
                self.onForeground()
            case .inactive:
                self.onForeground()
                self.onInactive()
            case .background:
                break
            @unknown default:
                break
            }
        }
        DispatchQueue.main.async(execute: workItem)
    }

    /**
     Удаляет наблюдатель из центра уведомлений при освобождении объекта.
     */
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}