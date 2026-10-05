import Foundation

/**
 Хранит настройки сбора стандартных параметров.
 */
public struct TrackingOptions {
    /**
     Множество стандартных параметров, которые не нужно добавлять к событиям.
     */
    public let disabledFields: Set<StandardParam>

    /**
     Создает настройки сбора стандартных параметров.
     - Parameters:
       - disabledFields: Множество стандартных параметров, которые не нужно добавлять к событиям.
     */
    public init(disabledFields: Set<StandardParam> = []) {
        self.disabledFields = disabledFields
    }

    /**
     Проверяет, включен ли стандартный параметр.
     - Parameters:
       - param: Стандартный параметр для проверки.
     - Returns: Флаг включения стандартного параметра.
     */
    public func isEnabled(_ param: StandardParam) -> Bool {
        !disabledFields.contains(param)
    }
}