import Foundation

/// Validates external dependencies against existing Tuist/Package.swift
struct TuistPackageValidator {

    struct ValidationResult {
        let missingDependencies: [ExternalDependency]
        let mismatchedDependencies: [(required: ExternalDependency, existing: ExternalDependency)]
    }

    let verbose: Bool

    init(verbose: Bool = false) {
        self.verbose = verbose
    }

    /// Validate dependencies against existing Tuist/Package.swift using JSON parsing
    func validate(
        dependencies: [ExternalDependency],
        rootDirectory: URL,
        customTuistDir: String?
    ) async -> ValidationResult {
        // Determine Tuist directory
        let tuistDir: URL
        if let custom = customTuistDir {
            tuistDir = URL(fileURLWithPath: custom)
        } else {
            tuistDir = rootDirectory.appendingPathComponent("Tuist")
        }

        let packagePath = tuistDir.appendingPathComponent("Package.swift")

        // Check if Package.swift exists
        guard FileManager.default.fileExists(atPath: packagePath.path) else {
            if verbose {
                print("Note: No existing Tuist/Package.swift found at \(packagePath.path)")
            }
            return ValidationResult(
                missingDependencies: dependencies,
                mismatchedDependencies: []
            )
        }

        // Load package description using JSON parsing
        let loader = PackageDescriptionLoader(verbose: verbose)
        guard let description = try? await loader.loadPackageDescription(at: packagePath) else {
            if verbose {
                print("Warning: Could not parse Tuist/Package.swift, assuming all dependencies are missing")
            }
            return ValidationResult(
                missingDependencies: dependencies,
                mismatchedDependencies: []
            )
        }

        // Parse existing dependencies from the package description
        let existingDeps = parseExistingDependencies(from: description)

        var missing: [ExternalDependency] = []
        var mismatched: [(required: ExternalDependency, existing: ExternalDependency)] = []

        for dep in dependencies {
            let normalizedUrl = dep.url.lowercased()
            if let existingDep = existingDeps[normalizedUrl] {
                // Check if requirements match
                if !requirementsMatch(required: dep.requirement, existing: existingDep.requirement) {
                    mismatched.append((dep, existingDep))
                }
            } else {
                missing.append(dep)
            }
        }

        return ValidationResult(
            missingDependencies: missing,
            mismatchedDependencies: mismatched
        )
    }

    /// Parse existing dependencies from PackageDescription
    private func parseExistingDependencies(from description: PackageDescription) -> [String: ExternalDependency] {
        var result: [String: ExternalDependency] = [:]

        guard let deps = description.dependencies else { return result }

        for dep in deps where dep.type == "sourceControl" {
            guard let url = dep.url, let requirement = dep.requirement else { continue }

            let externalDep = createExternalDependency(
                identity: dep.identity,
                url: url,
                requirement: requirement
            )
            result[url.lowercased()] = externalDep
        }

        return result
    }

    /// Create ExternalDependency from PackageDescription.Dependency.Requirement
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

    /// Check if two requirements match
    private func requirementsMatch(
        required: ExternalDependency.DependencyRequirement,
        existing: ExternalDependency.DependencyRequirement
    ) -> Bool {
        switch (required, existing) {
        case let (.range(reqFrom, reqTo), .range(existFrom, existTo)):
            return reqFrom == existFrom && reqTo == existTo
        case let (.exact(reqVersion), .exact(existVersion)):
            return reqVersion == existVersion
        case let (.branch(reqBranch), .branch(existBranch)):
            return reqBranch == existBranch
        case let (.revision(reqRev), .revision(existRev)):
            return reqRev == existRev
        default:
            // Different requirement types don't match
            return false
        }
    }

    /// Generate the Swift code line for a dependency
    func generateDependencyLine(for dep: ExternalDependency) -> String {
        return ".package(url: \"\(dep.url)\", \(dep.requirement.swiftCode))"
    }

    /// Print warnings for missing/mismatched dependencies
    func printWarnings(result: ValidationResult) {
        if result.missingDependencies.isEmpty && result.mismatchedDependencies.isEmpty {
            return
        }

        print("")
        print("Warning: External dependency issues detected:")
        print("")

        if !result.missingDependencies.isEmpty {
            print("Missing dependencies in Tuist/Package.swift:")
            print("Add the following to your dependencies array:")
            print("")
            for dep in result.missingDependencies {
                print("    \(generateDependencyLine(for: dep)),")
            }
            print("")
        }

        if !result.mismatchedDependencies.isEmpty {
            print("Version mismatches in Tuist/Package.swift:")
            for (required, existing) in result.mismatchedDependencies {
                print("  Found:    \(generateDependencyLine(for: existing))")
                print("  Expected: \(generateDependencyLine(for: required))")
                print("")
            }
        }
    }
}

extension ExternalDependency.DependencyRequirement {
    /// Extract version string for comparison
    var versionString: String {
        switch self {
        case .range(let from, _):
            return from
        case .exact(let version):
            return version
        case .branch(let branch):
            return branch
        case .revision(let revision):
            return revision
        }
    }
}
