import Foundation

/**
 Логирует сообщения Clickstream SDK.
 */
internal struct ClickstreamLogger {

    private static let prefix = "[ClickstreamSDK]"

    /**
     Выводит сообщение в консоль с префиксом SDK.
     - Parameters:
       - message: Текст сообщения для вывода в консоль.
     */
    static func log(_ message: String) {
        print("\(prefix) \(message)")
    }
}