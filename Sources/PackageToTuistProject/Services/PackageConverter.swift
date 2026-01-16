import Foundation

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
    ) -> TuistProject {
        let packageDir = packagePath.deletingLastPathComponent()

        // Determine destinations from platforms
        let destinations = determineDestinations(from: package.platforms)

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

            let tuistTarget = convertTarget(
                target: target,
                package: package,
                packagePath: packagePath,
                collector: collector,
                allDescriptions: allDescriptions,
                destinations: destinations
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
        destinations: String
    ) -> TuistTarget {
        // Determine product type
        let productType: TuistTarget.ProductType
        if target.type == "test" {
            productType = .unitTests
        } else {
            productType = defaultProductType
        }

        // Build bundle ID
        let bundleId = "\(bundleIdPrefix).\(target.name)"

        // Buildable folders - the target's source path
        let buildableFolders = [target.path]

        // Convert dependencies
        var dependencies: [TuistDependency] = []

        // Add target dependencies (same package)
        if let targetDeps = target.targetDependencies {
            for dep in targetDeps {
                dependencies.append(.target(name: dep))
            }
        }

        // Add product dependencies (external or other packages)
        if let productDeps = target.productDependencies {
            for productName in productDeps {
                let dep = classifyProductDependency(
                    productName: productName,
                    package: package,
                    packagePath: packagePath,
                    collector: collector
                )
                dependencies.append(dep)
            }
        }

        if verbose {
            print("  Converting target: \(target.name) -> \(productType.rawValue)")
        }

        return TuistTarget(
            name: target.name,
            product: productType,
            bundleId: bundleId,
            buildableFolders: buildableFolders,
            dependencies: dependencies,
            destinations: destinations
        )
    }

    private func classifyProductDependency(
        productName: String,
        package: PackageDescription,
        packagePath: URL,
        collector: DependencyCollector
    ) -> TuistDependency {
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
                            return .project(path: localPath, target: productName)
                        }
                    }
                }
            }

            // Check if it might match another local package
            if let localPath = collector.localPackagePath(for: productName) {
                return .project(path: localPath, target: productName)
            }
        }

        // It's an external dependency
        return .external(name: productName)
    }

    private func determineDestinations(from platforms: [PackageDescription.Platform]?) -> String {
        guard let platforms = platforms, !platforms.isEmpty else {
            return ".iOS" // Default to iOS if no platforms specified
        }

        // For simplicity, return the first platform's destination
        // Could be enhanced to support multiple destinations
        let platform = platforms[0]
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
            return ".iOS"
        }
    }
}
