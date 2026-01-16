import Foundation

/// Main command that orchestrates the conversion process
struct ConvertCommand {
    let rootDirectory: String
    let bundleIdPrefix: String
    let productType: String
    let tuistDir: String?
    let dryRun: Bool
    let verbose: Bool

    func execute() async throws {
        let rootURL = URL(fileURLWithPath: rootDirectory).standardizedFileURL

        print("Scanning for packages in: \(rootURL.path)")

        // Phase 1: Discovery
        let scanner = PackageScanner(rootDirectory: rootURL, verbose: verbose)
        let packagePaths = try scanner.findPackages()

        if packagePaths.isEmpty {
            print("No Package.swift files found.")
            return
        }

        print("Found \(packagePaths.count) package(s)")

        // Load all package descriptions
        var descriptions: [URL: PackageDescription] = [:]
        for packagePath in packagePaths {
            do {
                let description = try await scanner.loadPackageDescription(at: packagePath)
                descriptions[packagePath] = description
                if verbose {
                    print("  Loaded: \(description.name)")
                }
            } catch {
                print("Warning: Could not load \(packagePath.path): \(error.localizedDescription)")
            }
        }

        // Phase 2: Build dependency collector
        var collector = DependencyCollector()

        // Register all local packages first
        for (packagePath, description) in descriptions {
            let packageDir = packagePath.deletingLastPathComponent()
            let relativePath = calculateRelativePath(from: rootURL, to: packageDir)

            // Register local package with its products
            let productNames = description.products.map { $0.name }
            collector.registerLocalPackage(
                identity: description.name,
                relativePath: relativePath,
                products: productNames
            )

            if verbose {
                print("Registered local package: \(description.name) at \(relativePath)")
            }
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

        // Phase 3: Convert packages
        let converter = PackageConverter(
            bundleIdPrefix: bundleIdPrefix,
            productType: productType,
            verbose: verbose
        )

        var projects: [TuistProject] = []
        let allDescriptions = Dictionary(
            uniqueKeysWithValues: descriptions.map { ($0.key.path, $0.value) }
        )

        for (packagePath, description) in descriptions {
            if verbose {
                print("Converting: \(description.name)")
            }

            // Update relative paths for this package's dependencies
            var packageCollector = collector
            updateRelativePaths(
                collector: &packageCollector,
                fromPackage: packagePath,
                descriptions: descriptions
            )

            let project = converter.convert(
                package: description,
                packagePath: packagePath,
                collector: packageCollector,
                allDescriptions: allDescriptions
            )
            projects.append(project)
        }

        // Phase 4: Write output
        let projectWriter = ProjectWriter()
        for project in projects {
            try projectWriter.write(project: project, dryRun: dryRun, verbose: verbose)
        }

        // Validate external dependencies against existing Tuist/Package.swift
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

        print("Conversion complete!")
        if !dryRun {
            print("Generated \(projects.count) Project.swift file(s)")
        }
    }

    private func calculateRelativePath(from base: URL, to target: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path

        // Simple relative path calculation
        // Find common prefix and calculate relative path
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

        // For each local package, calculate the relative path from this package
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
            // Default to a generic from requirement
            depRequirement = .range(from: "1.0.0", to: "2.0.0")
        }

        return ExternalDependency(
            identity: identity,
            url: url,
            requirement: depRequirement
        )
    }
}
