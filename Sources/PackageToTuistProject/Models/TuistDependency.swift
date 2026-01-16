import Foundation

/// Represents a dependency in Tuist format
enum TuistDependency: Equatable, Hashable {
    /// Dependency on a target within the same project
    case target(name: String)
    /// Dependency on a target from another local project
    case project(path: String, target: String)
    /// Dependency on an external package
    case external(name: String)

    var swiftCode: String {
        switch self {
        case .target(let name):
            return ".target(name: \"\(name)\")"
        case .project(let path, let target):
            return ".project(target: \"\(target)\", path: \"\(path)\")"
        case .external(let name):
            return ".external(name: \"\(name)\")"
        }
    }
}
