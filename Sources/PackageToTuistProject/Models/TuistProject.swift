import Foundation

/// Intermediate representation of a Tuist project
struct TuistProject {
    let name: String
    let path: String
    let targets: [TuistTarget]
}

/// Intermediate representation of a Tuist target
struct TuistTarget {
    let name: String
    let product: ProductType
    let bundleId: String
    let sourcesPath: String
    let dependencies: [TuistDependency]
    let destinations: String
    let deploymentTargets: String?
    let packageName: String
    /// Whether this target needs ENABLE_TESTING_SEARCH_PATHS=YES
    /// True for test targets or targets that import XCTest/Testing/StoreKitTest
    let needsTestingSearchPaths: Bool
    /// Swift compiler settings from Package.swift (enableUpcomingFeature, define, etc.)
    let swiftSettings: [SwiftSetting]?

    init(
        name: String,
        product: ProductType,
        bundleId: String,
        sourcesPath: String,
        dependencies: [TuistDependency],
        destinations: String,
        deploymentTargets: String?,
        packageName: String,
        needsTestingSearchPaths: Bool,
        swiftSettings: [SwiftSetting]? = nil
    ) {
        self.name = name
        self.product = product
        self.bundleId = bundleId
        self.sourcesPath = sourcesPath
        self.dependencies = dependencies
        self.destinations = destinations
        self.deploymentTargets = deploymentTargets
        self.packageName = packageName
        self.needsTestingSearchPaths = needsTestingSearchPaths
        self.swiftSettings = swiftSettings
    }

    enum ProductType: String {
        case staticFramework
        case framework
        case staticLibrary
        case unitTests

        var swiftCode: String {
            switch self {
            case .staticFramework: return ".staticFramework"
            case .framework: return ".framework"
            case .staticLibrary: return ".staticLibrary"
            case .unitTests: return ".unitTests"
            }
        }
    }
}

/// External dependency to be collected for Tuist/Package.swift
struct ExternalDependency: Equatable, Hashable {
    let identity: String
    let url: String
    let requirement: DependencyRequirement

    enum DependencyRequirement: Equatable, Hashable {
        case range(from: String, to: String)
        case exact(String)
        case branch(String)
        case revision(String)

        var swiftCode: String {
            switch self {
            case .range(let from, _):
                return "from: \"\(from)\""
            case .exact(let version):
                return "exact: \"\(version)\""
            case .branch(let branch):
                return "branch: \"\(branch)\""
            case .revision(let revision):
                return "revision: \"\(revision)\""
            }
        }
    }
}
