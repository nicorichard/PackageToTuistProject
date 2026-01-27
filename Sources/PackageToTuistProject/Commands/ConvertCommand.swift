import Foundation

/// Actor to track loading progress in a thread-safe way
actor LoadingProgress {
    private(set) var completed = 0
    let total: Int

    init(total: Int) {
        self.total = total
    }

    func increment(packageName: String) {
        completed += 1
        print("  [\(completed)/\(total)] Loaded \(packageName)")
        fflush(stdout)
    }

    func incrementFailed(path: String, error: String) {
        completed += 1
        print("  [\(completed)/\(total)] FAILED: \(path)")
        print("    Warning: \(error)")
        fflush(stdout)
    }

    /// Get current progress (for testing)
    func getCompleted() -> Int {
        return completed
    }
}

/// Actor to track processing progress in a thread-safe way
actor ProcessingProgress {
    private(set) var completed = 0
    let total: Int

    init(total: Int) {
        self.total = total
    }

    func increment(packageName: String) {
        completed += 1
        print("  [\(completed)/\(total)] \(packageName) ✓")
        fflush(stdout)
    }

    func incrementFailed(packageName: String, error: String) {
        completed += 1
        print("  [\(completed)/\(total)] \(packageName) ✗")
        print("    Error: \(error)")
        fflush(stdout)
    }
}

/// Main command that orchestrates the conversion process
struct ConvertCommand {
    let rootDirectory: String
    let bundleIdPrefix: String
    let productType: String
    let tuistDir: String?
    let dryRun: Bool
    let verbose: Bool
    let force: Bool

    /// Maximum number of concurrent package loads
    private let maxConcurrentLoads = 8

    init(
        rootDirectory: String,
        bundleIdPrefix: String,
        productType: String,
        tuistDir: String?,
        dryRun: Bool,
        verbose: Bool,
        force: Bool = false
    ) {
        self.rootDirectory = rootDirectory
        self.bundleIdPrefix = bundleIdPrefix
        self.productType = productType
        self.tuistDir = tuistDir
        self.dryRun = dryRun
        self.verbose = verbose
        self.force = force
    }

    /// Check if ALL packages can be skipped (all-or-nothing cache check).
    /// Returns true only if the oldest Project.swift is newer than the newest Package.swift.
    func canSkipAllPackages(packagePaths: [URL]) -> Bool {
        guard !packagePaths.isEmpty else { return false }

        let fm = FileManager.default
        var newestPackageSwift: Date?
        var oldestProjectSwift: Date?

        for packagePath in packagePaths {
            let projectPath = packagePath.deletingLastPathComponent()
                .appendingPathComponent("Project.swift")

            // If any Project.swift doesn't exist, we need to regenerate
            guard fm.fileExists(atPath: projectPath.path) else { return false }

            do {
                let pkgAttrs = try fm.attributesOfItem(atPath: packagePath.path)
                let projAttrs = try fm.attributesOfItem(atPath: projectPath.path)

                guard let pkgMod = pkgAttrs[.modificationDate] as? Date,
                      let projMod = projAttrs[.modificationDate] as? Date else {
                    return false
                }

                // Track the newest Package.swift
                if newestPackageSwift == nil || pkgMod > newestPackageSwift! {
                    newestPackageSwift = pkgMod
                }

                // Track the oldest Project.swift
                if oldestProjectSwift == nil || projMod < oldestProjectSwift! {
                    oldestProjectSwift = projMod
                }
            } catch {
                return false  // Regenerate if we can't read timestamps
            }
        }

        // Skip only if the oldest Project.swift is newer than the newest Package.swift
        guard let newest = newestPackageSwift, let oldest = oldestProjectSwift else {
            return false
        }

        return oldest > newest
    }

    func execute() async throws {
        let rootURL = URL(fileURLWithPath: rootDirectory).standardizedFileURL

        // Step 1: Discover packages
        print("[Step 1/3] Discovering packages in: \(rootURL.path)")

        let scanner = PackageScanner(rootDirectory: rootURL, verbose: verbose)
        let packagePaths = try scanner.findPackages()

        if packagePaths.isEmpty {
            print("No Package.swift files found.")
            return
        }

        print("Found \(packagePaths.count) package(s)")

        // All-or-nothing cache check: skip entire generation if all Project.swift files are up-to-date
        if !force && canSkipAllPackages(packagePaths: packagePaths) {
            print("\nAll packages are up-to-date. Use --force to regenerate.")
            return
        }

        // Step 2: Load all package descriptions in parallel
        print("\n[Step 2/3] Loading package descriptions (up to \(maxConcurrentLoads) in parallel)...")
        let descriptions = await loadPackageDescriptions(
            packagePaths: packagePaths,
            scanner: scanner
        )

        print("  Loaded \(descriptions.count) of \(packagePaths.count) package(s)")

        if descriptions.isEmpty {
            print("No packages could be loaded.")
            return
        }

        // Step 3: Process each package (build deps, convert, write)
        print("\n[Step 3/3] Processing packages...")
        try await processPackages(
            descriptions: descriptions,
            rootURL: rootURL
        )

        print("\nConversion complete!")
        if !dryRun {
            print("Generated \(descriptions.count) Project.swift file(s)")
        }
    }

    /// Load package descriptions in parallel with limited concurrency
    private func loadPackageDescriptions(
        packagePaths: [URL],
        scanner: PackageScanner
    ) async -> [URL: PackageDescription] {
        let progress = LoadingProgress(total: packagePaths.count)

        let descriptions = await withTaskGroup(
            of: (URL, PackageDescription?).self,
            returning: [URL: PackageDescription].self
        ) { group in
            var inFlight = 0
            var pathIterator = packagePaths.makeIterator()
            var descriptions: [URL: PackageDescription] = [:]

            // Start initial batch
            while inFlight < maxConcurrentLoads, let packagePath = pathIterator.next() {
                group.addTask {
                    await self.loadSinglePackage(
                        packagePath: packagePath,
                        scanner: scanner,
                        progress: progress
                    )
                }
                inFlight += 1
            }

            // As each completes, start the next
            for await (path, description) in group {
                if let desc = description {
                    descriptions[path] = desc
                }

                // Start next task if there are more
                if let packagePath = pathIterator.next() {
                    group.addTask {
                        await self.loadSinglePackage(
                            packagePath: packagePath,
                            scanner: scanner,
                            progress: progress
                        )
                    }
                }
            }

            print("  All package loading tasks completed")
            fflush(stdout)
            return descriptions
        }

        return descriptions
    }

    /// Load a single package description
    private func loadSinglePackage(
        packagePath: URL,
        scanner: PackageScanner,
        progress: LoadingProgress
    ) async -> (URL, PackageDescription?) {
        let packageDirName = packagePath.deletingLastPathComponent().lastPathComponent

        do {
            let description = try await scanner.loadPackageDescription(at: packagePath)
            // Skip packages without library products
            guard description.hasLibraryProduct else {
                await progress.incrementFailed(path: packageDirName, error: "No library product found, skipping")
                return (packagePath, nil)
            }
            await progress.increment(packageName: description.name)
            return (packagePath, description)
        } catch {
            await progress.incrementFailed(path: packageDirName, error: error.localizedDescription)
            return (packagePath, nil)
        }
    }

    /// Process each package: build collector, convert, and write
    private func processPackages(
        descriptions: [URL: PackageDescription],
        rootURL: URL
    ) async throws {
        // Pre-compute relative path matrix: O(n²) but only happens once
        let pathMatrix = buildPathMatrix(descriptions: descriptions)

        // Build base dependency collector with external dependencies only
        var baseCollector = DependencyCollector()

        // Collect external dependencies
        for description in descriptions.values {
            if let deps = description.dependencies {
                for dep in deps where dep.type == "sourceControl" {
                    if let url = dep.url, let requirement = dep.requirement {
                        let externalDep = createExternalDependency(
                            identity: dep.identity,
                            url: url,
                            requirement: requirement
                        )
                        baseCollector.registerExternalDependency(externalDep)
                    }
                }
            }
        }

        // Create converter and writer (both are thread-safe for different files)
        let converter = PackageConverter(
            bundleIdPrefix: bundleIdPrefix,
            productType: productType,
            verbose: verbose
        )
        let projectWriter = ProjectWriter()
        let allDescriptions = Dictionary(
            uniqueKeysWithValues: descriptions.map { ($0.key.path, $0.value) }
        )

        // Process packages in parallel with controlled concurrency
        let sortedDescriptions = descriptions.sorted { $0.value.name < $1.value.name }
        let progress = ProcessingProgress(total: descriptions.count)

        // Capture values for use in task group (Swift 6 concurrency safety)
        let isDryRun = dryRun
        let isVerbose = verbose
        let externalDepsCollector = baseCollector  // Immutable copy for task group

        try await withThrowingTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = sortedDescriptions.makeIterator()

            // Start initial batch
            while inFlight < maxConcurrentLoads, let (packagePath, description) = iterator.next() {
                group.addTask {
                    // Build per-package collector using pre-computed path matrix
                    let packageCollector = self.buildPackageCollector(
                        base: externalDepsCollector,
                        fromPackage: packagePath,
                        descriptions: descriptions,
                        pathMatrix: pathMatrix
                    )

                    // Convert
                    let project = try converter.convert(
                        package: description,
                        packagePath: packagePath,
                        collector: packageCollector,
                        allDescriptions: allDescriptions
                    )

                    // Write (each package writes to its own file)
                    try projectWriter.write(project: project, dryRun: isDryRun, verbose: isVerbose)
                    await progress.increment(packageName: description.name)
                }
                inFlight += 1
            }

            // As each completes, start the next
            for try await _ in group {
                if let (packagePath, description) = iterator.next() {
                    group.addTask {
                        let packageCollector = self.buildPackageCollector(
                            base: externalDepsCollector,
                            fromPackage: packagePath,
                            descriptions: descriptions,
                            pathMatrix: pathMatrix
                        )

                        let project = try converter.convert(
                            package: description,
                            packagePath: packagePath,
                            collector: packageCollector,
                            allDescriptions: allDescriptions
                        )

                        try projectWriter.write(project: project, dryRun: isDryRun, verbose: isVerbose)
                        await progress.increment(packageName: description.name)
                    }
                }
            }
        }

        // Validate external dependencies
        let externalDeps = externalDepsCollector.allExternalDependencies()
        if !externalDeps.isEmpty {
            let validator = TuistPackageValidator()
            let tuistRootDir = rootURL.deletingLastPathComponent()
            let result = validator.validate(
                dependencies: externalDeps,
                rootDirectory: tuistRootDir,
                customTuistDir: tuistDir,
                verbose: verbose
            )
            validator.printWarnings(result: result)
        }
    }

    /// Pre-compute all pairwise relative paths between packages
    private func buildPathMatrix(
        descriptions: [URL: PackageDescription]
    ) -> [URL: [URL: String]] {
        var matrix: [URL: [URL: String]] = [:]

        for fromPath in descriptions.keys {
            let fromDir = fromPath.deletingLastPathComponent()
            matrix[fromPath] = [:]

            for toPath in descriptions.keys {
                let toDir = toPath.deletingLastPathComponent()
                matrix[fromPath]![toPath] = calculateRelativePath(from: fromDir, to: toDir)
            }
        }

        return matrix
    }

    /// Build a collector for a specific package using pre-computed paths
    private func buildPackageCollector(
        base: DependencyCollector,
        fromPackage packagePath: URL,
        descriptions: [URL: PackageDescription],
        pathMatrix: [URL: [URL: String]]
    ) -> DependencyCollector {
        var collector = base

        // Register all local packages with paths relative to this package
        for (otherPath, otherDescription) in descriptions {
            let relativePath = pathMatrix[packagePath]![otherPath]!
            let products = otherDescription.products.map { (name: $0.name, targets: $0.targets) }

            collector.registerLocalPackage(
                identity: otherDescription.name,
                relativePath: relativePath,
                products: products
            )
        }

        return collector
    }

    private func calculateRelativePath(from base: URL, to target: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path

        let baseComponents = basePath.split(separator: "/")
        let targetComponents = targetPath.split(separator: "/")

        var commonLength = 0
        for (b, t) in zip(baseComponents, targetComponents) {
            if b == t {
                commonLength += 1
            } else {
                break
            }
        }

        let upCount = baseComponents.count - commonLength
        let downPath = targetComponents.dropFirst(commonLength)

        var result = Array(repeating: "..", count: upCount)
        result.append(contentsOf: downPath.map(String.init))

        return result.joined(separator: "/")
    }

    private func createExternalDependency(
        identity: String,
        url: String,
        requirement: PackageDescription.Dependency.Requirement
    ) -> ExternalDependency {
        let depRequirement: ExternalDependency.DependencyRequirement

        if let range = requirement.range?.first {
            depRequirement = .range(from: range.lowerBound, to: range.upperBound)
        } else if let exact = requirement.exact?.first {
            depRequirement = .exact(exact)
        } else if let branch = requirement.branch?.first {
            depRequirement = .branch(branch)
        } else if let revision = requirement.revision?.first {
            depRequirement = .revision(revision)
        } else {
            depRequirement = .range(from: "1.0.0", to: "2.0.0")
        }

        return ExternalDependency(
            identity: identity,
            url: url,
            requirement: depRequirement
        )
    }
}
