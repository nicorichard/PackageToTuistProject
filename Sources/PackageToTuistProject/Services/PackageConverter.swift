import Foundation

/// Errors that can occur during package conversion
enum PackageConversionError: Error, CustomStringConvertible {
    case unresolvableProductDependency(product: String, package: String, matchedIdentity: String)
    case missingPlatforms(package: String)

    var description: String {
        switch self {
        case .unresolvableProductDependency(let product, let package, let matchedIdentity):
            return "Cannot resolve targets for product '\(product)' in package '\(package)'. " +
                   "The dependency matched local package '\(matchedIdentity)' but no targets could be found. " +
                   "Ensure the product name in your Package.swift dependency matches an actual product in the target package."
        case .missingPlatforms(let package):
            return """
                Package '\(package)' does not specify any platforms.

                Tuist requires explicit deployment targets, so packages must declare their supported platforms.

                Add a platforms declaration to your Package.swift, for example:

                    let package = Package(
                        name: "\(package)",
                        platforms: [
                            .iOS(.v15),
                            .macOS(.v12)
                        ],
                        ...
                    )
                """
        }
    }
}

/// Converts SPM package descriptions to Tuist project representations
struct PackageConverter {
    let bundleIdPrefix: String
    let defaultProductType: TuistTarget.ProductType
    let verbose: Bool

    init(
        bundleIdPrefix: String,
        productType: String,
        verbose: Bool = false
    ) {
        self.bundleIdPrefix = bundleIdPrefix
        self.defaultProductType = TuistTarget.ProductType(rawValue: productType) ?? .staticFramework
        self.verbose = verbose
    }

    /// Convert a package description to a Tuist project
    func convert(
        package: PackageDescription,
        packagePath: URL,
        collector: DependencyCollector,
        allDescriptions: [String: PackageDescription]
    ) throws -> TuistProject {
        // Validate that platforms are specified
        guard let platforms = package.platforms, !platforms.isEmpty else {
            throw PackageConversionError.missingPlatforms(package: package.name)
        }

        let packageDir = packagePath.deletingLastPathComponent()

        // Determine destinations and deployment targets from platforms
        let destinations = determineDestinations(from: platforms)
        let deploymentTargets = determineDeploymentTargets(from: platforms)

        // Collect binary target names for dependency resolution
        let binaryTargetNames = Set(package.targets.filter { $0.type == "binary" }.map { $0.name })

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
                binaryTargetNames: binaryTargetNames
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
        binaryTargetNames: Set<String>
    ) throws -> TuistTarget {
        // Determine product type
        let productType: TuistTarget.ProductType
        if target.type == "test" {
            productType = .unitTests
        } else {
            productType = defaultProductType
        }

        // Determine if target needs testing search paths by scanning for testing framework imports
        // (Tuist handles test targets automatically, so we only need to detect helper libraries)
        let scanner = ImportScanner()
        let needsTestingSearchPaths = scanner.needsTestingSearchPaths(
            packagePath: packagePath.path,
            targetPath: target.path,
            sources: target.sources
        )

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

        return TuistTarget(
            name: target.name,
            product: productType,
            bundleId: bundleId,
            sourcesPath: sourcesPath,
            dependencies: uniqueDependencies,
            destinations: destinations,
            deploymentTargets: deploymentTargets,
            packageName: package.name,
            needsTestingSearchPaths: needsTestingSearchPaths,
            swiftSettings: target.swiftSettings
        )
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
