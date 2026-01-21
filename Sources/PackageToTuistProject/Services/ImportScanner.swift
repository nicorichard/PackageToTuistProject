import Foundation

/// Scans Swift source files to detect testing framework imports
struct ImportScanner {
    /// Frameworks that require ENABLE_TESTING_SEARCH_PATHS
    private static let testingFrameworks = ["XCTest", "Testing", "StoreKitTest"]

    /// Check if any source file in the target imports a testing framework
    func needsTestingSearchPaths(
        packagePath: String,
        targetPath: String,
        sources: [String]?
    ) -> Bool {
        let packageDir = URL(fileURLWithPath: packagePath).deletingLastPathComponent()
        let targetDir = packageDir.appendingPathComponent(targetPath)

        // Get all Swift files to scan
        let swiftFiles: [URL]
        if let sources = sources, !sources.isEmpty {
            // Use explicit sources list
            swiftFiles = sources.map { targetDir.appendingPathComponent($0) }
                .filter { $0.pathExtension == "swift" }
        } else {
            // Fall back to scanning all .swift files in target directory
            swiftFiles = findSwiftFiles(in: targetDir)
        }

        // Check each file for testing imports
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            if containsTestingImport(fileContent: content) {
                return true
            }
        }

        return false
    }

    /// Check if a single file contains testing framework imports
    func containsTestingImport(fileContent: String) -> Bool {
        // Remove block comments first
        let contentWithoutBlockComments = removeBlockComments(from: fileContent)

        // Check each line
        let lines = contentWithoutBlockComments.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip single-line comments
            if trimmedLine.hasPrefix("//") {
                continue
            }

            // Check for testing framework imports
            // Match exact module names only (not partial matches like XCTestExtensions)
            for framework in Self.testingFrameworks {
                // Match "import XCTest" exactly (not "import XCTestExtensions")
                let importPattern = "import \(framework)"
                if trimmedLine == importPattern ||
                   trimmedLine.hasPrefix(importPattern + " ") ||
                   trimmedLine.hasPrefix(importPattern + "\t") {
                    return true
                }
            }
        }

        return false
    }

    /// Remove block comments from content
    private func removeBlockComments(from content: String) -> String {
        var result = content
        // Simple approach: remove /* ... */ blocks
        while let startRange = result.range(of: "/*") {
            if let endRange = result.range(of: "*/", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                // Unclosed block comment - remove everything from start
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
                break
            }
        }
        return result
    }

    /// Find all Swift files in a directory recursively
    private func findSwiftFiles(in directory: URL) -> [URL] {
        var swiftFiles: [URL] = []

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return swiftFiles
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL)
            }
        }

        return swiftFiles
    }
}
