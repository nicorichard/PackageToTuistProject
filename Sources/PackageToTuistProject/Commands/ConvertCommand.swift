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

/// Main command that orchestrates the conversion process
struct ConvertCommand {
    let rootDirectory: String
    let bundleIdPrefix: String
    let productType: String
    let tuistDir: String?
    let dryRun: Bool
    let verbose: Bool

    /// Maximum number of concurrent package loads
    private let maxConcurrentLoads = 8

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

        return await withTaskGroup(
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
        // Build base dependency collector with all packages
        var collector = DependencyCollector()

        // Register all local packages
        for (packagePath, description) in descriptions {
            let packageDir = packagePath.deletingLastPathComponent()
            let relativePath = calculateRelativePath(from: rootURL, to: packageDir)
            let productNames = description.products.map { $0.name }
            collector.registerLocalPackage(
                identity: description.name,
                relativePath: relativePath,
                products: productNames
            )
        }

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
                        collector.registerExternalDependency(externalDep)
                    }
                }
            }
        }

        // Create converter and writer
        let converter = PackageConverter(
            bundleIdPrefix: bundleIdPrefix,
            productType: productType,
            verbose: verbose
        )
        let projectWriter = ProjectWriter()
        let allDescriptions = Dictionary(
            uniqueKeysWithValues: descriptions.map { ($0.key.path, $0.value) }
        )

        // Process each package: convert and write
        let sortedDescriptions = descriptions.sorted { $0.value.name < $1.value.name }
        for (index, (packagePath, description)) in sortedDescriptions.enumerated() {
            print("  [\(index + 1)/\(descriptions.count)] \(description.name)", terminator: "")
            fflush(stdout)

            // Update relative paths for this package's dependencies
            var packageCollector = collector
            updateRelativePaths(
                collector: &packageCollector,
                fromPackage: packagePath,
                descriptions: descriptions
            )

            // Convert
            let project = converter.convert(
                package: description,
                packagePath: packagePath,
                collector: packageCollector,
                allDescriptions: allDescriptions
            )

            // Write
            try projectWriter.write(project: project, dryRun: dryRun, verbose: verbose)
            print(" ✓")
        }

        // Validate external dependencies
        let externalDeps = collector.allExternalDependencies()
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

    private func updateRelativePaths(
        collector: inout DependencyCollector,
        fromPackage packagePath: URL,
        descriptions: [URL: PackageDescription]
    ) {
        let packageDir = packagePath.deletingLastPathComponent()

        for (otherPath, otherDescription) in descriptions {
            let otherDir = otherPath.deletingLastPathComponent()
            let relativePath = calculateRelativePath(from: packageDir, to: otherDir)

            collector.registerLocalPackage(
                identity: otherDescription.name,
                relativePath: relativePath,
                products: otherDescription.products.map { $0.name }
            )
        }
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
