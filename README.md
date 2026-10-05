# ClickStream SDK — iOS

iOS SDK для трекинга кликстрим-событий.

Реализован как Swift Package и подключается в проекты через Swift Package Manager по git-URL.

## Установка

### Swift Package Manager

1. В Xcode откройте: `File → Add Package Dependencies`.
2. Вставьте git-URL репозитория:
```
https://github.com/freedomdata/clickstream-ios-sdk
```
3. В `Dependency Rule` выберите Branch → нужная версия SDK, например 1.0.0.
4. Нажмите `Add Package`.
5. Добавьте `ClickstreamSDK` в target вашего приложения.