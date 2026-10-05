import Foundation

/**
 Описывает стандартные параметры, которые SDK может добавлять к событиям.
 */
public enum StandardParam: String, CaseIterable, Hashable {
    /**
     Идентификатор устройства.
     */
    case deviceId = "deviceId"

    /**
     Имя события.
     */
    case eventName = "eventName"

    /**
     Дата события.
     */
    case eventDate = "eventDate"

    /**
     Идентификатор сессии.
     */
    case sessionId = "sessionId"

    /**
     Идентификатор пользователя.
     */
    case userId = "userId"

    /**
     Версия приложения.
     */
    case appVersion = "appVersion"

    /**
     Название операционной системы.
     */
    case osName = "osName"

    /**
     Версия операционной системы.
     */
    case osVersion = "osVersion"

    /**
     Текущая локаль устройства.
     */
    case locale = "locale"

    /**
     Модель устройства.
     */
    case deviceModel = "deviceModel"

    /**
     Оператор сотовой связи.
     */
    case carrier = "carrier"

    /**
     Часовой пояс устройства.
     */
    case timezone = "timezone"

    /**
     Тип текущей сети.
     */
    case networkType = "networkType"

    /**
     Версия SDK.
     */
    case sdkVersion = "sdkVersion"

    /**
     Контекст устройства.
     */
    case deviceContext = "deviceContext"
}