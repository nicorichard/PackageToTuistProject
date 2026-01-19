import Foundation

/// Collects and deduplicates external dependencies across all packages
struct DependencyCollector {
    /// Map of package identity to external dependency info
    private var externalDependencies: [String: ExternalDependency] = [:]

    /// Map of local package identity to its path (relative to root)
    private var localPackages: [String: String] = [:]

    /// Map of product name to the package identity that provides it
    private var productToPackage: [String: String] = [:]

    /// Map of product name to the targets it contains
    private var productToTargets: [String: [String]] = [:]

    /// Map of package identity to its product names
    private var packageToProducts: [String: [String]] = [:]

    /// Register a local package and its products
    mutating func registerLocalPackage(
        identity: String,
        relativePath: String,
        products: [(name: String, targets: [String])]
    ) {
        localPackages[identity.lowercased()] = relativePath
        packageToProducts[identity.lowercased()] = products.map { $0.name }
        for product in products {
            productToPackage[product.name] = identity
            productToTargets[product.name] = product.targets
        }
    }

    /// Register an external dependency
    mutating func registerExternalDependency(_ dependency: ExternalDependency) {
        let key = dependency.identity.lowercased()
        // Keep the first registered version (could enhance to detect conflicts)
        if externalDependencies[key] == nil {
            externalDependencies[key] = dependency
        }
    }

    /// Check if a package identity is a local package
    func isLocalPackage(identity: String) -> Bool {
        return localPackages[identity.lowercased()] != nil
    }

    /// Get the relative path to a local package
    func localPackagePath(for identity: String) -> String? {
        return localPackages[identity.lowercased()]
    }

    /// Find which package provides a product
    func packageIdentity(forProduct product: String) -> String? {
        return productToPackage[product]
    }

    /// Get the targets that a product contains
    func targets(forProduct product: String) -> [String]? {
        return productToTargets[product]
    }

    /// Get all product names for a package identity
    func products(forPackage identity: String) -> [String]? {
        return packageToProducts[identity.lowercased()]
    }

    /// Get all targets for all products in a package
    func allTargets(forPackage identity: String) -> [String]? {
        guard let productNames = packageToProducts[identity.lowercased()] else {
            return nil
        }
        var allTargets: [String] = []
        for productName in productNames {
            if let targets = productToTargets[productName] {
                for target in targets where !allTargets.contains(target) {
                    allTargets.append(target)
                }
            }
        }
        return allTargets.isEmpty ? nil : allTargets
    }

    /// Get all collected external dependencies
    func allExternalDependencies() -> [ExternalDependency] {
        return Array(externalDependencies.values).sorted { $0.identity < $1.identity }
    }

    /// Classify a dependency based on context
    func classifyDependency(
        productName: String,
        currentPackagePath: URL,
        targetDependencies: [String],
        descriptions: [String: PackageDescription]
    ) -> TuistDependency {
        // First check if it's a same-package target dependency
        if targetDependencies.contains(productName) {
            return .target(name: productName)
        }

        // Check if product maps to a local package
        if let packageIdentity = productToPackage[productName],
           let relativePath = localPackages[packageIdentity.lowercased()]
        {
            return .project(path: relativePath, target: productName)
        }

        // Otherwise it's an external dependency
        return .external(name: productName)
    }
}
