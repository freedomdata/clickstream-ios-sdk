# Инструкции для AI code review

Этот файл предназначен для GitLab Duo и других AI-агентов, которые проверяют merge request в проекте `ClickstreamSDK`.

## Контекст проекта

`ClickstreamSDK` - iOS SDK для отправки clickstream-событий из мобильных приложений. Проект реализован как Swift Package Manager package.

Основные параметры проекта:

- Package: `ClickstreamSDK`.
- Swift tools version: `6.2`.
- Минимальная платформа: iOS `14`.
- Основной target: `ClickstreamSDK`.
- Test target: `ClickstreamSDKTests`.
- Публичный модуль: `ClickstreamSDK`.
- Сетевой endpoint: `POST <baseUrl>/event`.
- Авторизация: заголовок `Authorization` со значением `apiKey`.
- Хранилища: `UserDefaults` для сессии и device id, `Application Support/com.clickstream.sdk/events` для offline-очереди.
- Основные системные API: `Foundation`, `UIKit`, `Network`, `CoreTelephony`.

## Структура кода

Основные зоны кода:

- `Package.swift` - описание Swift package, targets и минимальной iOS-платформы.
- `Sources/ClickstreamSDK/ClickstreamSDK.swift` - публичная точка входа SDK, инициализация, сбор payload, user id, user properties, autotracking, flush.
- `ClickstreamConfig.swift` - публичная конфигурация SDK и default-значения.
- `TrackingOptions.swift`, `StandardParam.swift` - управление стандартными полями payload.
- `EventApiClient.swift` - JSON-сериализация и HTTP-отправка событий.
- `EventQueue.swift`, `OfflineEventStore.swift`, `StoredEvent.swift` - offline-очередь, persistent storage, batch flush.
- `RetryPolicy.swift`, `RetryOrchestrator.swift` - классификация retry/drop/remove и backoff.
- `SessionManager.swift`, `SessionStorage.swift` - жизненный цикл сессии и хранение состояния.
- `AppLifecycleObserver.swift` - подписка на foreground/background/terminate через `NotificationCenter` и `UIApplication`.
- `AutoTracker.swift`, `ScreenTracking.swift` - автособытия `app_start`, `app_close`, `screen_view`, `deeplink_open`.
- `DeviceContextProvider.swift`, `DeviceIdProvider.swift`, `NetworkMonitor.swift`, `TimeUtils.swift` - device context, network type, timezone, даты.
- `UserPropertiesContextMerger.swift` - объединение custom user properties и SDK context.
- `Tests/ClickstreamSDKTests` - unit-тесты по компонентам SDK.

## Общие правила ревью

Проверяй только изменения MR и затронутый ими контекст. Не требуй несвязанных рефакторингов, если они не нужны для корректности, безопасности, совместимости SDK или поддержки изменяемого поведения.

Пиши комментарии на русском языке. Каждый комментарий должен содержать:

- конкретный риск или дефект;
- ссылку на файл и строку;
- объяснение, почему это важно для iOS SDK или приложений-потребителей;
- практичное предложение по исправлению.

Приоритет ревью:

1. Ошибки поведения, регрессии публичного API, потеря событий, дубли событий, падения в runtime.
2. Безопасность и приватность: `apiKey`, HTTPS, персональные данные, небезопасные логи, persistent storage.
3. Совместимость iOS: iOS 14+, lifecycle, background behavior, UIKit/SwiftUI edge cases, threading.
4. Надежность offline-очереди, retry, batch flush, network monitoring и storage.
5. Конкурентность, serial queues, locks, отмена задач, отсутствие гонок.
6. Наличие и качество тестов.
7. Читаемость, поддерживаемость и соответствие стилю Swift-кода проекта.

Если серьезных проблем нет, явно напиши, что блокирующих замечаний не найдено, и укажи, какие проверки или тесты желательно выполнить.

## Публичный API SDK

Изменения в публичных типах и методах проверяй особенно строго:

- `ClickstreamSDK.initialize(config:)`.
- `ClickstreamSDK.trackEvent(_:props:)`.
- `ClickstreamSDK.setUserId(_:)`, `clearUserId()`.
- `ClickstreamSDK.setUserProperties(_:)`.
- `ClickstreamSDK.setAutoTrackingEnabled(_:)`, `isAutoTrackingEnabled()`.
- `ClickstreamSDK.reportDeeplinkOpen(_:)`.
- `ClickstreamSDK.reportScreenView(_:)`.
- `ClickstreamSDK.flush()`.
- `ClickstreamSDK.setTrackingOptions(_:)`.
- `ClickstreamConfig`.
- `TrackingOptions`.
- `StandardParam`.

Проверяй совместимость для приложений-потребителей:

- Не ломается ли source compatibility без явной необходимости.
- Не меняются ли default-значения `ClickstreamConfig` так, что SDK начинает чаще отправлять данные, дольше хранить события, быстрее расходовать батарею или иначе вести себя в существующих приложениях.
- Не меняются ли payload keys, которые ожидает backend: `eventName`, `eventDate`, `deviceId`, `sessionId`, `clientId`, `context`.
- Не меняется ли семантика `setUserId`, `clearUserId`, `setUserProperties`, autotracking и `flush`.
- Не появляются ли исключения или `precondition` в публичных путях, где SDK раньше безопасно логировал проблему и возвращался.
- Не блокирует ли публичный вызов main thread длительной работой: сетью, файловым I/O, тяжелой JSON-сериализацией, ожиданием semaphore или serial queue.

Публичный API лучше расширять обратно совместимо: добавлять опциональные параметры с безопасными default-значениями, новые enum cases и новые методы без изменения существующих контрактов.

## Конфигурация и безопасность

Особое внимание уделяй `apiKey`, `baseUrl` и пользовательским данным:

- `baseUrl` должен оставаться HTTPS-only. Ослаблять проверку до HTTP нельзя, кроме явно изолированного тестового кода.
- `apiKey`, headers авторизации, device id, user id и полный payload не должны попадать в небезопасные production-логи.
- Не добавляй логирование сырых request/response body, headers или исключений, содержащих секреты.
- Не сохраняй `apiKey` в `UserDefaults`, файлы offline-очереди или другое persistent storage.
- Не добавляй сбор чувствительных данных устройства без явной необходимости и контроля через `TrackingOptions`.
- Если меняется `DeviceContextProvider`, проверь, что отключение `.deviceContext` и отдельных `StandardParam` реально исключает поля из payload.
- Если меняется `setUserProperties`, проверь, что клиентские ключи не перетираются SDK context без явного правила.

## События и payload

Для логики событий проверяй:

- Пользовательские `props` не теряются при добавлении стандартных параметров.
- Порядок merge не позволяет неожиданно подменить критичные поля без осознанного решения.
- `eventDate` и timezone формируются стабильно и покрыты тестами.
- `TrackingOptions` отключает выбранные стандартные поля для всех релевантных событий.
- `clientId` добавляется только при установленном user id.
- `context` добавляется к `session_start` и `user_properties` согласно текущему контракту.
- `null`, пустые строки, пустые словари, массивы, вложенные структуры и не-JSON-сериализуемые значения обрабатываются предсказуемо.
- Ошибка JSON-сериализации не должна приводить к падению приложения-потребителя, если падение не является явно выбранным контрактом.

Если изменение добавляет новое стандартное поле, проверь соответствие:

- `StandardParam`;
- JSON key mapping;
- `TrackingOptions`;
- `DeviceContextProvider`;
- тесты payload и отключения поля.

## Lifecycle и автотрекинг

При изменениях lifecycle-кода проверяй:

- `AppLifecycleObserver.subscribe()` идемпотентен и не создает дублирующиеся observers.
- `unsubscribe()` и `deinit` корректно очищают `NotificationCenter` observers.
- SDK не хранит сильные ссылки на `UIViewController`, SwiftUI view или callback потребителя дольше необходимого.
- Инициализация в already-active приложении корректно синхронизируется с текущим `UIApplication.applicationState`.
- `app_start` и `app_close` не дублируются при быстрых foreground/background, inactive transitions, terminate и повторном init.
- `screen_view` учитывает throttle, `previousScreen`, SwiftUI hosting controllers, presentations и ручной `reportScreenView`.
- `deeplink_open` отправляется только при включенном autotracking и не теряется при типичных AppDelegate/SceneDelegate/SwiftUI `.onOpenURL` сценариях.
- Background task в terminate-пути завершается и не держит приложение дольше нужного.
- `DispatchSemaphore` или синхронные ожидания не попадают в main-thread пути, где могут подвесить приложение.

## Сессии

Для `SessionManager` и `SessionStorage` проверяй:

- Новая сессия стартует при первом событии и после `sessionTimeoutMs`.
- `lastActiveTime`, `lastBackgroundTime`, pending app close и `sessionId` согласованно сохраняются и очищаются.
- Повторные foreground/background transitions не создают дубли `session_start` и `session_end`.
- `session_end` при terminate использует критичный путь отправки и корректный `sessionId`.
- Восстановление после restart/crash не отправляет ложные события и не оставляет старое состояние в `UserDefaults`.
- Тесты изолируют `UserDefaults`, чтобы состояние одного теста не влияло на другой.

## Сеть, retry и offline-очередь

Для `EventApiClient`, `EventQueue`, `OfflineEventStore`, `RetryPolicy` и `RetryOrchestrator` проверяй:

- Endpoint формируется корректно при `baseUrl` с завершающим `/` и без него.
- HTTP `2xx` считается успехом, `429` и `5xx` retryable, обычные `4xx` non-retryable.
- Transport errors и timeout не приводят к потере события, если retry еще возможен.
- Non-retryable ошибки удаляют событие из очереди и не создают бесконечный retry loop.
- События удаляются из offline storage только после успеха, non-retryable результата, битого payload или исчерпания retry.
- `maxQueueSize` ограничивает рост storage и удаляет самые старые события.
- `flushQueueSize`, `flushBatchSize`, `flushIntervalMillis` и `maxFlushProcessingTimeMs` не создают гонок и дублей отправки.
- `isFlushing` действительно гарантирует не более одного активного flush.
- При потере сети flush останавливается без удаления события; при восстановлении сети запускается с debounce.
- Записи в `Application Support` используют атомарную запись, file protection и исключение из backup.
- Поврежденные файлы очереди и индекс `queue_index.json` обрабатываются без падения приложения.

Если MR меняет очередь, storage, retry или network monitor, нужны тесты на success, retryable error, non-retryable error, max retries, восстановление сети, corrupted storage и concurrent flush.

## Конкурентность

Проверяй:

- Доступ к состоянию `ClickstreamSDK` идет через `com.clickstream.sdk.state`.
- `SessionManager`, `AutoTracker`, `EventQueue`, `NetworkMonitor` не читают и не пишут shared state без serial queue или lock.
- Синхронные `queue.sync` не вызываются рекурсивно с той же очереди.
- Closures с `self` используют weak-ссылки там, где есть риск retain cycle.
- `nonisolated(unsafe)` и static mutable state применяются только там, где есть внешняя синхронизация.
- Completion callback вызывается ровно один раз, особенно в timeout/network paths.
- Асинхронные retries и periodic flush не оставляют бесконечно живущие work items без необходимости.

Не предлагай переводить весь код на Swift Concurrency только ради стиля. Это оправдано, только если реально упрощает отмену, тестирование или жизненный цикл.

## Совместимость iOS

При iOS-изменениях проверяй:

- Код работает начиная с iOS 14.
- API, доступные только на новых версиях iOS, защищены availability check.
- Использование `UIKit`, `Network`, `CoreTelephony`, file protection и background tasks корректно для SDK, подключаемого в чужое приложение.
- SDK не добавляет лишние permissions, services, background modes или entitlements без крайней необходимости.
- Поведение SwiftUI и UIKit не ломается для приложений с SceneDelegate, AppDelegate и SwiftUI `@main App`.
- Публичные символы не используют слишком общие имена за пределами модуля.

## Производительность

Оценивай производительность там, где изменение может повлиять на приложение-потребитель:

- Работа на main thread: сеть, файловый I/O, JSON, semaphore, долгие locks.
- Частота автособытий и flush-задач.
- Размер batch и частота retry.
- Повторный сбор device context на каждое событие.
- Рост offline-очереди при плохой сети.
- Логирование больших payload или объектов.

Не требуй микрооптимизаций для редких путей, если нет риска для батареи, памяти, responsiveness или потери событий.

## Package, сборка и публикация

При изменениях в `Package.swift`, README, CI или release metadata проверяй:

- Package name, product name и target names остаются согласованными: `ClickstreamSDK`.
- Минимальная iOS-платформа не повышается без явного обоснования.
- Новые зависимости действительно нужны SDK, а не приложению-потребителю.
- Новая зависимость не увеличивает surface area SDK без причины и имеет приемлемую лицензию.
- Публичные инструкции установки через Swift Package Manager остаются корректными.
- Команды сборки и тестов в CI соответствуют iOS/UIKit коду.

Локальная проверка, если доступен Xcode/macOS toolchain:

- `xcodebuild test -scheme ClickstreamSDK -destination 'platform=iOS Simulator,name=iPhone 15'`
- `swift test` использовать только если текущая Swift toolchain в этом окружении может собрать package с iOS/UIKit-зависимостями.

## Тесты

Для каждого MR оценивай, достаточно ли тестов для измененной логики.

Нужны тесты, если добавлены или изменены:

- публичный API или default-значения `ClickstreamConfig`;
- формирование payload;
- `setUserProperties` и merge user context;
- autotracking, screen tracking и lifecycle;
- сессии и восстановление состояния;
- network result classification;
- retry/backoff/batch processing;
- offline storage;
- device context и `TrackingOptions`;
- обработка ошибок, edge cases и конкурентность.

Тесты должны проверять не только happy path, но и граничные случаи:

- SDK не инициализирован;
- повторный `initialize(config:)`;
- `nil`, пустые и не-JSON-сериализуемые значения;
- отсутствие сети;
- `2xx`, `429`, `4xx`, `5xx`, transport error;
- несколько событий в очереди;
- параллельные `trackEvent`/`flush`;
- corrupted files в offline storage;
- разные состояния приложения: active, inactive, background, terminate.

Если тест сложно написать из-за текущей архитектуры, предложи минимальное изменение для тестируемости без большого рефакторинга.

## Качество Swift-кода

Проверяй:

- Public API документирован понятным DocC-style комментарием.
- `internal` используется для деталей реализации SDK.
- Ошибки не валят приложение-потребитель, если SDK может безопасно деградировать.
- `precondition` используется только для действительно недопустимой конфигурации с понятным сообщением.
- Нет `print`, `debugPrint`, `dump`, `fatalError`, временных TODO/FIXME и debug-кода в production-путях.
- `@preconcurrency`, `nonisolated(unsafe)` и suppression-подходы имеют понятную причину.
- Nullable-типы отражают реальный контракт.
- Нет ненужного глобального mutable state или неочищаемых singleton-ссылок.
- Нет несвязанных форматирований, переименований и рефакторингов вне задачи MR.

Не требуй абстракцию ради абстракции. Замечание по дублированию оставляй только если оно повышает риск расхождения поведения, усложняет сопровождение или копирует уже существующую проектную логику.

## Ограничения AI-ревьюера

Не придумывай несуществующие классы, backend API или внутренние библиотеки. Если точного подтверждения в diff или доступном контексте нет, формулируй рекомендацию как проверку.

Плохо:

`Используй BackendEventNormalizer.normalize(...)`

Хорошо:

`Проверь, нет ли уже существующего helper для нормализации payload в модуле SDK. Если есть, лучше переиспользовать его, чтобы не поддерживать две реализации одного правила.`

Не оставляй формальные замечания, которые не меняют качество SDK. Комментарии должны помогать предотвратить конкретный баг, регрессию, риск безопасности, проблему совместимости или потерю событий.
