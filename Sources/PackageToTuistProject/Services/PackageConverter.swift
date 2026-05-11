import Foundation

/// Errors that can occur during package conversion
enum PackageConversionError: Error, CustomStringConvertible {
    case unresolvableProductDependency(product: String, package: String, matchedIdentity: String)

    var description: String {
        switch self {
        case .unresolvableProductDependency(let product, let package, let matchedIdentity):
            return "Cannot resolve targets for product '\(product)' in package '\(package)'. " +
                   "The dependency matched local package '\(matchedIdentity)' but no targets could be found. " +
                   "Ensure the product name in your Package.swift dependency matches an actual product in the target package."
        }
    }
}

/// Converts SPM package descriptions to Tuist project representations
struct PackageConverter {
    /// SPM "safe minimum" platforms used when a package doesn't declare any.
    /// See: https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageModel/Platform.swift#L40
    static let defaultPlatforms: [PackageDescription.Platform] = [
        .init(name: "ios", version: "12.0"),
        .init(name: "macos", version: "10.13"),
        .init(name: "tvos", version: "12.0"),
        .init(name: "watchos", version: "4.0"),
        .init(name: "visionos", version: "1.0"),
    ]

    let bundleIdPrefix: String
    let defaultProductType: TuistTarget.ProductType
    let verbose: Bool
    let platformFilter: Set<SupportedPlatform>?

    init(
        bundleIdPrefix: String,
        productType: String,
        verbose: Bool = false,
        platformFilter: Set<SupportedPlatform>? = nil
    ) {
        self.bundleIdPrefix = bundleIdPrefix
        self.defaultProductType = TuistTarget.ProductType(rawValue: productType) ?? .staticFramework
        self.verbose = verbose
        self.platformFilter = platformFilter
    }

    /// Convert a package description to a Tuist project
    /// Returns nil if the package has no matching platforms after filtering
    func convert(
        package: PackageDescription,
        packagePath: URL,
        collector: DependencyCollector,
        allDescriptions: [String: PackageDescription]
    ) throws -> TuistProject? {
        // Use package platforms if specified, otherwise fall back to SPM safe minimums
        var platforms = (package.platforms?.isEmpty == false)
            ? package.platforms!
            : Self.defaultPlatforms

        // Apply platform filter if specified
        if let filter = platformFilter {
            platforms = platforms.filter { platform in
                filter.contains { $0.matches(platform) }
            }
            // Skip package if no platforms match the filter
            if platforms.isEmpty {
                if verbose {
                    print("  Skipping \(package.name): no matching platforms")
                }
                return nil
            }
        }

        let packageDir = packagePath.deletingLastPathComponent()

        // Determine destinations and deployment targets from platforms
        let destinations = determineDestinations(from: platforms)
        let deploymentTargets = determineDeploymentTargets(from: platforms)

        // Collect binary target names for dependency resolution
        let binaryTargetNames = Set(package.targets.filter { $0.type == "binary" }.map { $0.name })

        let packageDefaultSwiftVersion = Self.packageDefaultSwiftVersion(for: package)

        // Convert each target
        var tuistTargets: [TuistTarget] = []
        for target in package.targets {
            // Skip executable targets
            if target.type == "executable" {
                if verbose {
                    print("  Skipping executable target: \(target.name)")
                }
                continue
            }

            // Skip binary targets - they become external dependencies
            if target.type == "binary" {
                if verbose {
                    print("  Skipping binary target (will be external): \(target.name)")
                }
                continue
            }

            let tuistTarget = try convertTarget(
                target: target,
                package: package,
                packagePath: packagePath,
                collector: collector,
                allDescriptions: allDescriptions,
                destinations: destinations,
                deploymentTargets: deploymentTargets,
                binaryTargetNames: binaryTargetNames,
                packageDefaultSwiftVersion: packageDefaultSwiftVersion
            )
            tuistTargets.append(tuistTarget)
        }

        return TuistProject(
            name: package.name,
            path: packageDir.path,
            targets: tuistTargets
        )
    }

    private func convertTarget(
        target: PackageDescription.Target,
        package: PackageDescription,
        packagePath: URL,
        collector: DependencyCollector,
        allDescriptions: [String: PackageDescription],
        destinations: String,
        deploymentTargets: String?,
        binaryTargetNames: Set<String>,
        packageDefaultSwiftVersion: String?
    ) throws -> TuistTarget {
        // Determine product type
        let productType: TuistTarget.ProductType
        if target.type == "test" {
            productType = .unitTests
        } else {
            productType = defaultProductType
        }

        // Build bundle ID
        let bundleId = "\(bundleIdPrefix).\(target.name)"

        // Sources path - the target's source path
        let sourcesPath = target.path

        // Convert dependencies
        var dependencies: [TuistDependency] = []

        // Add target dependencies (same package)
        if let targetDeps = target.targetDependencies {
            for dep in targetDeps {
                // Binary targets become external dependencies
                if binaryTargetNames.contains(dep) {
                    dependencies.append(.external(name: dep))
                } else {
                    dependencies.append(.target(name: dep))
                }
            }
        }

        // Add product dependencies (external or other packages)
        if let productDeps = target.productDependencies {
            for productName in productDeps {
                let deps = try classifyProductDependency(
                    productName: productName,
                    package: package,
                    packagePath: packagePath,
                    collector: collector
                )
                dependencies.append(contentsOf: deps)
            }
        }

        // Deduplicate dependencies (products may share targets)
        let uniqueDependencies = dependencies.reduce(into: [TuistDependency]()) { result, dep in
            if !result.contains(dep) {
                result.append(dep)
            }
        }

        if verbose {
            print("  Converting target: \(target.name) -> \(productType.rawValue)")
        }

        // Resolve Swift language version: a per-target `.swiftLanguageMode(...)` setting
        // overrides the package-level default. The mode setting is consumed here (not
        // emitted as a flag) — Xcode's SWIFT_VERSION drives the language mode.
        var remainingSettings = target.swiftSettings
        var targetSwiftVersion: String?
        if let settings = remainingSettings {
            for setting in settings {
                if case .swiftLanguageMode(let v) = setting.kind {
                    targetSwiftVersion = v
                    break
                }
            }
            remainingSettings = settings.filter {
                if case .swiftLanguageMode = $0.kind { return false }
                return true
            }
            if remainingSettings?.isEmpty == true {
                remainingSettings = nil
            }
        }
        let resolvedSwiftVersion = targetSwiftVersion ?? packageDefaultSwiftVersion

        return TuistTarget(
            name: target.name,
            product: productType,
            bundleId: bundleId,
            sourcesPath: sourcesPath,
            dependencies: uniqueDependencies,
            destinations: destinations,
            deploymentTargets: deploymentTargets,
            packageName: package.name,
            swiftSettings: remainingSettings,
            swiftVersion: resolvedSwiftVersion
        )
    }

    /// Resolve the package-level default Swift language version.
    /// Prefers the highest entry in `swiftLanguageVersions` (if declared), else the
    /// major component of `toolsVersion`. Returns nil if neither is available.
    static func packageDefaultSwiftVersion(for package: PackageDescription) -> String? {
        if let declared = package.swiftLanguagesVersions, !declared.isEmpty {
            return declared.max { lhs, rhs in
                lhs.compare(rhs, options: .numeric) == .orderedAscending
            }
        }
        if let tools = package.toolsVersion {
            return tools.split(separator: ".").first.map(String.init)
        }
        return nil
    }

    private func classifyProductDependency(
        productName: String,
        package: PackageDescription,
        packagePath: URL,
        collector: DependencyCollector
    ) throws -> [TuistDependency] {
        // Check if there's a known product-to-targets mapping (local package)
        if let targets = collector.targets(forProduct: productName),
           let packageIdentity = collector.packageIdentity(forProduct: productName),
           let localPath = collector.localPackagePath(for: packageIdentity)
        {
            // Return a dependency for each target in the product
            return targets.map { .project(path: localPath, target: $0) }
        }

        // Check if the product comes from a local package dependency
        if let deps = package.dependencies {
            for dep in deps {
                if dep.type == "fileSystem" {
                    // Local package - check if it provides this product
                    let identity = dep.identity
                    if let localPath = collector.localPackagePath(for: identity) {
                        // This product likely comes from this local package
                        // Product name often matches or relates to package identity
                        let identityLower = identity.lowercased()
                        let productLower = productName.lowercased()

                        // Check if product name matches the package identity pattern
                        if productLower == identityLower ||
                            productLower.contains(identityLower) ||
                            identityLower.contains(productLower)
                        {
                            // First try direct product lookup
                            if let targets = collector.targets(forProduct: productName), !targets.isEmpty {
                                return targets.map { .project(path: localPath, target: $0) }
                            }
                            // Fall back to all targets from this package
                            if let targets = collector.allTargets(forPackage: identity), !targets.isEmpty {
                                return targets.map { .project(path: localPath, target: $0) }
                            }
                            throw PackageConversionError.unresolvableProductDependency(
                                product: productName,
                                package: package.name,
                                matchedIdentity: identity
                            )
                        }
                    }
                }
            }

            // Check if it might match another local package
            if let localPath = collector.localPackagePath(for: productName) {
                // First try direct product lookup
                if let targets = collector.targets(forProduct: productName), !targets.isEmpty {
                    return targets.map { .project(path: localPath, target: $0) }
                }
                // Fall back to all targets from this package
                if let targets = collector.allTargets(forPackage: productName), !targets.isEmpty {
                    return targets.map { .project(path: localPath, target: $0) }
                }
                throw PackageConversionError.unresolvableProductDependency(
                    product: productName,
                    package: package.name,
                    matchedIdentity: productName
                )
            }
        }

        // It's an external dependency
        return [.external(name: productName)]
    }

    private func determineDestinations(from platforms: [PackageDescription.Platform]) -> String {
        // Convert all platforms to Tuist destination format
        let destinations = platforms.compactMap { platform -> String? in
            switch platform.name.lowercased() {
            case "ios":
                return ".iOS"
            case "macos":
                return ".macOS"
            case "tvos":
                return ".tvOS"
            case "watchos":
                return ".watchOS"
            case "visionos":
                return ".visionOS"
            default:
                return nil
            }
        }

        // Single destination: .iOS
        // Multiple destinations: Destinations([Destinations.iOS, .macOS].flatMap { $0 })
        if destinations.count == 1 {
            return destinations[0]
        }
        let list = "Destinations\(destinations[0]), " + destinations.dropFirst().joined(separator: ", ")
        return "Destinations([\(list)].flatMap { $0 })"
    }

    private func determineDeploymentTargets(from platforms: [PackageDescription.Platform]) -> String? {
        // Collect versions by platform
        var versions: [String: String] = [:]
        for platform in platforms {
            switch platform.name.lowercased() {
            case "ios":
                versions["iOS"] = platform.version
            case "macos":
                versions["macOS"] = platform.version
            case "watchos":
                versions["watchOS"] = platform.version
            case "tvos":
                versions["tvOS"] = platform.version
            case "visionos":
                versions["visionOS"] = platform.version
            default:
                break
            }
        }

        guard !versions.isEmpty else {
            return nil
        }

        // Single platform: .iOS("15.0")
        // Multiple platforms: .multiplatform(iOS: "15.0", macOS: "12.0")
        // Order must be: iOS, macOS, watchOS, tvOS, visionOS
        if versions.count == 1 {
            let (key, version) = versions.first!
            return ".\(key)(\"\(version)\")"
        }

        let orderedKeys = ["iOS", "macOS", "watchOS", "tvOS", "visionOS"]
        let args = orderedKeys.compactMap { key -> String? in
            guard let version = versions[key] else { return nil }
            return "\(key): \"\(version)\""
        }.joined(separator: ", ")
        return ".multiplatform(\(args))"
    }
}
