import Foundation

/**
 Описывает флаг с набором значений.
 */
public struct FlagInfo: Codable, Sendable, Equatable {
    public let id: String?
    public let name: String?
    public let values: [FlagValue]?

    /**
     Создает описание флага.
     - Parameters:
       - id: Идентификатор флага.
       - name: Имя флага.
       - values: Список значений флага.
     */
    public init(id: String?, name: String?, values: [FlagValue]?) {
        self.id = id
        self.name = name
        self.values = values
    }
}

/**
 Описывает значение флага и условия его применения.
 */
public struct FlagValue: Codable, Sendable, Equatable {
    public let id: String?
    public let value: String?
    public let isDefault: Bool?
    public let conditions: [FlagCondition]?

    /**
     Создает значение флага.
     - Parameters:
       - id: Идентификатор значения.
       - value: Значение флага.
       - isDefault: Признак значения по умолчанию.
       - conditions: Условия применения значения.
     */
    public init(id: String?, value: String?, isDefault: Bool?, conditions: [FlagCondition]?) {
        self.id = id
        self.value = value
        self.isDefault = isDefault
        self.conditions = conditions
    }
}

/**
 Описывает условие выбора значения флага.
 */
public struct FlagCondition: Codable, Sendable, Equatable {
    public let id: String?
    public let type: String?
    public let values: [String]?
    public let customValue: [String: FlagJSONValue]?

    /**
     Создает условие выбора значения флага.
     - Parameters:
       - id: Идентификатор условия.
       - type: Тип условия.
       - values: Список значений условия.
       - customValue: Пользовательские параметры условия.
     */
    public init(id: String?, type: String?, values: [String]?, customValue: [String: FlagJSONValue]?) {
        self.id = id
        self.type = type
        self.values = values
        self.customValue = customValue
    }
}

/**
 Представляет JSON-значение в пользовательских параметрах условия флага.
 */
public enum FlagJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    /**
     Декодирует JSON-значение из контейнера.
     - Parameter decoder: Декодер JSON.
     */
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    /**
     Кодирует JSON-значение в контейнер.
     - Parameter encoder: Кодировщик JSON.
     */
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/**
 Описывает результат запроса конфигурации флагов.
 */
public enum FetchFlagsResult: Sendable {
    case success([FlagInfo])
    case fallback([FlagInfo])
    case failure(FlagsFetchError)
}

/**
 Описывает ошибку запроса конфигурации флагов.
 */
public enum FlagsFetchError: Error, Sendable, Equatable {
    case notInitialized
    case noCachedFlags
    case invalidUrl
    case invalidResponse
    case httpError(Int)
    case networkUnavailable
    case requestTimedOut
    case requestFailed
}
