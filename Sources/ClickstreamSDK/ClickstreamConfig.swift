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
     Номер попытки, после которого экспоненциальная часть backoff перестает расти.
     */
    public let flushMaxRetries: Int

    /**
     Максимальный размер offline-очереди событий.
     */
    public let maxQueueSize: Int

    /**
     Интервал отправки неполного batch после появления первого события в миллисекундах.
     */
    public let flushIntervalMillis: TimeInterval

    /**
     Максимальное количество событий в одном batch и порог немедленной отправки.
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
       - flushMaxRetries: Номер попытки, после которого экспоненциальная часть backoff перестает расти.
       - maxQueueSize: Максимальный размер offline-очереди событий.
       - flushIntervalMillis: Интервал отправки неполного batch после появления первого события.
       - flushBatchSize: Максимальное количество событий в одном batch и порог немедленной отправки.
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
        flushMaxRetries: Int = 5,
        maxQueueSize: Int = 1000,
        flushIntervalMillis: TimeInterval = 10_000,
        flushBatchSize: Int = 50,
        maxFlushProcessingTimeMs: TimeInterval = 5000,
        networkDebounceMs: TimeInterval = 500
    ) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.sessionTimeoutMs = sessionTimeoutMs
        self.autoTrackingEnabled = autoTrackingEnabled
        self.trackingOptions = trackingOptions
        self.sdkVersion = sdkVersion
        self.flushMaxRetries = flushMaxRetries
        self.maxQueueSize = maxQueueSize
        self.flushIntervalMillis = flushIntervalMillis
        self.flushBatchSize = flushBatchSize
        self.maxFlushProcessingTimeMs = maxFlushProcessingTimeMs
        self.networkDebounceMs = networkDebounceMs
    }
}
