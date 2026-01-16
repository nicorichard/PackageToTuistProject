import Foundation

/// Validates external dependencies against existing Tuist/Package.swift
struct TuistPackageValidator {

    struct ValidationResult {
        let missingDependencies: [ExternalDependency]
        let mismatchedDependencies: [(required: ExternalDependency, existing: String)]
    }

    /// Validate dependencies against existing Tuist/Package.swift
    func validate(
        dependencies: [ExternalDependency],
        rootDirectory: URL,
        customTuistDir: String?,
        verbose: Bool
    ) -> ValidationResult {
        // Determine Tuist directory
        let tuistDir: URL
        if let custom = customTuistDir {
            tuistDir = URL(fileURLWithPath: custom)
        } else {
            tuistDir = rootDirectory.appendingPathComponent("Tuist")
        }

        let packagePath = tuistDir.appendingPathComponent("Package.swift")

        // Read existing Package.swift
        guard let existingContent = try? String(contentsOf: packagePath, encoding: .utf8) else {
            if verbose {
                print("Note: No existing Tuist/Package.swift found at \(packagePath.path)")
            }
            return ValidationResult(
                missingDependencies: dependencies,
                mismatchedDependencies: []
            )
        }

        // Parse existing dependencies (simple regex-based parsing)
        let existingDeps = parseExistingDependencies(from: existingContent)

        var missing: [ExternalDependency] = []
        var mismatched: [(required: ExternalDependency, existing: String)] = []

        for dep in dependencies {
            if let existingLine = existingDeps[dep.url.lowercased()] {
                // Check if requirements roughly match
                if !existingLine.contains(dep.requirement.versionString) {
                    mismatched.append((dep, existingLine))
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

    /// Parse existing .package() declarations from Package.swift content
    private func parseExistingDependencies(from content: String) -> [String: String] {
        var result: [String: String] = [:]

        // Match .package(url: "...", ...)
        let pattern = #"\.package\s*\(\s*url:\s*"([^"]+)"[^)]*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            if let fullRange = Range(match.range, in: content),
               let urlRange = Range(match.range(at: 1), in: content)
            {
                let url = String(content[urlRange]).lowercased()
                let fullLine = String(content[fullRange])
                result[url] = fullLine
            }
        }

        return result
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
        print("⚠️  External dependency warnings:")
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
                print("  Found:    \(existing)")
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
