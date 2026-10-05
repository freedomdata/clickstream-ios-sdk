import Foundation

/**
 Предоставляет методы для форматирования даты и смещения таймзоны.
 */
internal enum TimeUtils {

    private static let formatterLock = NSLock()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    /**
     Возвращает текущую дату с локальным смещением таймзоны.
     - Returns: Текущая дата в формате ISO со смещением таймзоны.
     */
    static func nowWithOffset() -> String {
        let now = Date()
        return formatWithOffset(date: now)
    }

    /**
     Форматирует дату с локальным смещением таймзоны.
     - Parameters:
       - date: Дата для форматирования.
     - Returns: Дата в формате ISO со смещением таймзоны.
     */
    static func formatWithOffset(date: Date) -> String {
        formatterLock.lock()
        dateFormatter.timeZone = TimeZone.current
        let dateString = dateFormatter.string(from: date)
        formatterLock.unlock()
        let offsetString = tzOffsetString(for: TimeZone.current, at: date)
        return dateString + offsetString
    }

    /**
     Возвращает смещение таймзоны для указанной даты.
     - Parameters:
       - timeZone: Таймзона для вычисления смещения.
       - date: Дата для вычисления смещения.
     - Returns: Смещение таймзоны в формате ±HH:mm.
     */
    static func tzOffsetString(for timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%@%02d:%02d", sign, hours, minutes)
    }
}