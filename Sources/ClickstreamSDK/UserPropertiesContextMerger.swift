import Foundation

/**
 Объединяет пользовательские свойства профиля с параметрами SDK.
 */
internal enum UserPropertiesContextMerger {

    /**
     Объединяет пользовательские параметры с параметрами SDK без перезаписи пользовательских значений.
     - Parameters:
       - custom: Пользовательские параметры профиля.
       - sdkParams: Параметры SDK для добавления в контекст.
     - Returns: Объединенный словарь параметров контекста.
     */
    static func merge(custom: [String: Any], sdkParams: [String: Any?]) -> [String: Any] {
        var merged: [String: Any] = [:]
        merged.merge(custom) { _, new in new }
        for (key, value) in sdkParams {
            if merged[key] == nil {
                merged[key] = value ?? NSNull()
            }
        }
        return merged
    }
}