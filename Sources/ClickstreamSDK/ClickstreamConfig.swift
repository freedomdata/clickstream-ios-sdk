import Foundation

/**
 Хранит параметры инициализации Clickstream SDK.
 */
public struct ClickstreamConfig {
    /**
     API-ключ для подключения к Clickstream backend.
     */
    public let apiKey: String

    /**
     Базовый URL Clickstream backend.
     */
    public let baseUrl: String

    /**
     Таймаут сессии в миллисекундах.
     */
    public let sessionTimeoutMs: TimeInterval

    /**
     Определяет, включен ли автосбор стандартных событий.
     */
    public let autoTrackingEnabled: Bool

    /**
     Хранит настройки сбора стандартных параметров.
     */
    public let trackingOptions: TrackingOptions

    /**
     Версия SDK для параметров контекста.
     */
    public let sdkVersion: String

    /**
     Количество событий в очереди для автоматического запуска flush.
     */
    public let flushQueueSize: Int

    /**
     Максимальное количество повторных попыток отправки событий.
     */
    public let flushMaxRetries: Int

    /**
     Максимальный размер offline-очереди событий.
     */
    public let maxQueueSize: Int

    /**
     Интервал периодического flush накопленных событий в миллисекундах.
     */
    public let flushIntervalMillis: TimeInterval

    /**
     Максимальное количество успешно отправленных событий за один проход flush.
     */
    public let flushBatchSize: Int

    /**
     Максимальное время одного прохода flush в миллисекундах.
     */
    public let maxFlushProcessingTimeMs: TimeInterval

    /**
     Минимальный интервал между обработками восстановления сети в миллисекундах.
     */
    public let networkDebounceMs: TimeInterval

    /**
     Создает конфигурацию Clickstream SDK с параметрами подключения и отправки событий.
     - Parameters:
       - apiKey: API-ключ для подключения к Clickstream backend.
       - baseUrl: Базовый URL Clickstream backend.
       - sessionTimeoutMs: Таймаут сессии в миллисекундах.
       - autoTrackingEnabled: Флаг включения автосбора стандартных событий.
       - trackingOptions: Настройки сбора стандартных параметров.
       - sdkVersion: Версия SDK для параметров контекста.
       - flushQueueSize: Количество событий в очереди для автоматического запуска flush.
       - flushMaxRetries: Максимальное количество повторных попыток отправки событий.
       - maxQueueSize: Максимальный размер offline-очереди событий.
       - flushIntervalMillis: Интервал периодического flush накопленных событий в миллисекундах.
       - flushBatchSize: Максимальное количество успешно отправленных событий за один проход flush.
       - maxFlushProcessingTimeMs: Максимальное время одного прохода flush в миллисекундах.
       - networkDebounceMs: Минимальный интервал между обработками восстановления сети в миллисекундах.
     */
    public init(
        apiKey: String,
        baseUrl: String,
        sessionTimeoutMs: TimeInterval = 5 * 60 * 1000,
        autoTrackingEnabled: Bool = true,
        trackingOptions: TrackingOptions = TrackingOptions(),
        sdkVersion: String = "0.0.0",
        flushQueueSize: Int = 20,
        flushMaxRetries: Int = 5,
        maxQueueSize: Int = 1000,
        flushIntervalMillis: TimeInterval = 30_000,
        flushBatchSize: Int = 20,
        maxFlushProcessingTimeMs: TimeInterval = 5000,
        networkDebounceMs: TimeInterval = 500
    ) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.sessionTimeoutMs = sessionTimeoutMs
        self.autoTrackingEnabled = autoTrackingEnabled
        self.trackingOptions = trackingOptions
        self.sdkVersion = sdkVersion
        self.flushQueueSize = flushQueueSize
        self.flushMaxRetries = flushMaxRetries
        self.maxQueueSize = maxQueueSize
        self.flushIntervalMillis = flushIntervalMillis
        self.flushBatchSize = flushBatchSize
        self.maxFlushProcessingTimeMs = maxFlushProcessingTimeMs
        self.networkDebounceMs = networkDebounceMs
    }
}