import ArgumentParser

/// Represents a platform that can be used for filtering in the CLI
enum SupportedPlatform: String, CaseIterable, ExpressibleByArgument, Hashable {
    case iOS
    case macOS
    case tvOS
    case watchOS
    case visionOS

    /// Case-insensitive initialization from string
    init?(argument: String) {
        let lowercased = argument.lowercased()
        switch lowercased {
        case "ios":
            self = .iOS
        case "macos":
            self = .macOS
        case "tvos":
            self = .tvOS
        case "watchos":
            self = .watchOS
        case "visionos":
            self = .visionOS
        default:
            return nil
        }
    }

    /// Check if this platform matches a PackageDescription.Platform
    func matches(_ platform: PackageDescription.Platform) -> Bool {
        switch self {
        case .iOS:
            return platform.name.lowercased() == "ios"
        case .macOS:
            return platform.name.lowercased() == "macos"
        case .tvOS:
            return platform.name.lowercased() == "tvos"
        case .watchOS:
            return platform.name.lowercased() == "watchos"
        case .visionOS:
            return platform.name.lowercased() == "visionos"
        }
    }
}
