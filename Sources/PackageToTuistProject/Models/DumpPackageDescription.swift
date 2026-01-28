import Foundation

/// Codable types for `swift package dump-package` output
/// This has a different structure than `swift package describe --type json`

struct DumpPackageDescription: Codable {
    let name: String
    let targets: [DumpTarget]
}

struct DumpTarget: Codable {
    let name: String
    let settings: [DumpSetting]?
}

struct DumpSetting: Codable {
    let kind: DumpSettingKind
    let tool: String
    let condition: DumpSettingCondition?
}

struct DumpSettingCondition: Codable {
    let config: String?
    let platformNames: [String]?
}

/// The kind of setting from dump-package JSON
/// Handles the nested "_0" structure used by Swift Package Manager
enum DumpSettingKind: Codable, Equatable {
    case enableUpcomingFeature(String)
    case enableExperimentalFeature(String)
    case define(String)
    case unsafeFlags([String])
    case unknown

    private struct StringValue: Codable {
        let _0: String
    }

    private struct ArrayValue: Codable {
        let _0: [String]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Find which key is present
        if let key = container.allKeys.first {
            switch key.stringValue {
            case "enableUpcomingFeature":
                let value = try container.decode(StringValue.self, forKey: key)
                self = .enableUpcomingFeature(value._0)
            case "enableExperimentalFeature":
                let value = try container.decode(StringValue.self, forKey: key)
                self = .enableExperimentalFeature(value._0)
            case "define":
                let value = try container.decode(StringValue.self, forKey: key)
                self = .define(value._0)
            case "unsafeFlags":
                let value = try container.decode(ArrayValue.self, forKey: key)
                self = .unsafeFlags(value._0)
            default:
                self = .unknown
            }
        } else {
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        switch self {
        case .enableUpcomingFeature(let value):
            try container.encode(StringValue(_0: value), forKey: DynamicCodingKey(stringValue: "enableUpcomingFeature"))
        case .enableExperimentalFeature(let value):
            try container.encode(StringValue(_0: value), forKey: DynamicCodingKey(stringValue: "enableExperimentalFeature"))
        case .define(let value):
            try container.encode(StringValue(_0: value), forKey: DynamicCodingKey(stringValue: "define"))
        case .unsafeFlags(let values):
            try container.encode(ArrayValue(_0: values), forKey: DynamicCodingKey(stringValue: "unsafeFlags"))
        case .unknown:
            break
        }
    }
}

/// Dynamic coding key for handling variable JSON keys
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Conversion to SwiftSetting

extension DumpSetting {
    /// Convert a dump-package setting to our SwiftSetting type
    /// Returns nil for non-swift settings or unknown kinds
    func toSwiftSetting() -> SwiftSetting? {
        // Only process swift settings
        guard tool == "swift" else { return nil }

        let settingKind: SwiftSettingKind
        switch kind {
        case .enableUpcomingFeature(let value):
            settingKind = .enableUpcomingFeature(value)
        case .enableExperimentalFeature(let value):
            settingKind = .enableExperimentalFeature(value)
        case .define(let value):
            settingKind = .define(value)
        case .unsafeFlags(let values):
            settingKind = .unsafeFlags(values)
        case .unknown:
            return nil
        }

        let settingCondition: SwiftSettingCondition?
        if let condition = condition {
            settingCondition = SwiftSettingCondition(
                config: condition.config,
                platformNames: condition.platformNames?.isEmpty == true ? nil : condition.platformNames
            )
        } else {
            settingCondition = nil
        }

        return SwiftSetting(kind: settingKind, condition: settingCondition)
    }
}
