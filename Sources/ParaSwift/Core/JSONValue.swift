import Foundation

/// Helper type to encode arbitrary JSON values
struct JSONValue: Encodable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let dict = value as? [String: Any] {
            try container.encode(JSONDictionary(dict))
        } else if let array = value as? [Any] {
            try container.encode(array.map { JSONValue($0) })
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if value is NSNull {
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Cannot encode value of type \(type(of: value))"
            ))
        }
    }
}

struct JSONDictionary: Encodable {
    let dictionary: [String: Any]
    
    init(_ dictionary: [String: Any]) {
        self.dictionary = dictionary
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        
        for (key, value) in dictionary {
            let codingKey = DynamicCodingKey(stringValue: key)!
            try container.encode(JSONValue(value), forKey: codingKey)
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}