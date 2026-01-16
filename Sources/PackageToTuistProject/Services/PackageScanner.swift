import Foundation

/// Scans a directory for Swift packages and loads their descriptions
struct PackageScanner {
    let rootDirectory: URL
    let verbose: Bool

    /// Timeout for each package describe operation (in seconds)
    private let timeoutSeconds: UInt64 = 60

    /// Directories to exclude from scanning
    private let excludedDirectories: Set<String> = [
        ".build",
        ".git",
        "Derived",
        "DerivedData",
        ".swiftpm",
        "Tuist",
        "node_modules",
        "Pods",
    ]

    init(rootDirectory: URL, verbose: Bool = false) {
        self.rootDirectory = rootDirectory
        self.verbose = verbose
    }

    /// Find all Package.swift files in the directory tree
    func findPackages() throws -> [URL] {
        var packages: [URL] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScannerError.cannotEnumerateDirectory(rootDirectory.path)
        }

        while let url = enumerator.nextObject() as? URL {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                let directoryName = url.lastPathComponent
                if excludedDirectories.contains(directoryName) {
                    enumerator.skipDescendants()
                    continue
                }

                let packageSwiftURL = url.appendingPathComponent("Package.swift")
                if fileManager.fileExists(atPath: packageSwiftURL.path) {
                    packages.append(packageSwiftURL)
                    if verbose {
                        print("Found package: \(packageSwiftURL.path)")
                    }
                }
            }
        }

        return packages
    }

    /// Load package description using `swift package describe --type json` with timeout
    func loadPackageDescription(at packagePath: URL) async throws -> PackageDescription {
        let packageDirectory = packagePath.deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "describe", "--type", "json"]
        process.currentDirectoryURL = packageDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if verbose {
            print("Loading package description: \(packageDirectory.path)")
        }

        try process.run()

        // Wait for process with timeout
        let completed = await waitForProcessWithTimeout(process: process, timeoutSeconds: timeoutSeconds)

        if !completed {
            // Process timed out - kill it
            process.terminate()
            // Give it a moment to terminate gracefully
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if process.isRunning {
                // Force kill if still running
                kill(process.processIdentifier, SIGKILL)
            }
            throw ScannerError.timeout(packageDirectory.path, timeoutSeconds)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ScannerError.packageDescribeFailed(packageDirectory.path, errorMessage)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(PackageDescription.self, from: outputData)
        } catch {
            throw ScannerError.jsonDecodingFailed(packageDirectory.path, error.localizedDescription)
        }
    }

    /// Wait for a process to complete with a timeout
    private func waitForProcessWithTimeout(process: Process, timeoutSeconds: UInt64) async -> Bool {
        let timeoutNanoseconds = timeoutSeconds * 1_000_000_000

        return await withTaskGroup(of: Bool.self) { group in
            // Task 1: Wait for process to complete
            group.addTask {
                process.waitUntilExit()
                return true
            }

            // Task 2: Timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            // Return the first result (either completion or timeout)
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return false
        }
    }

    enum ScannerError: LocalizedError {
        case cannotEnumerateDirectory(String)
        case packageDescribeFailed(String, String)
        case jsonDecodingFailed(String, String)
        case timeout(String, UInt64)

        var errorDescription: String? {
            switch self {
            case .cannotEnumerateDirectory(let path):
                return "Cannot enumerate directory: \(path)"
            case .packageDescribeFailed(let path, let message):
                return "Failed to describe package at \(path): \(message)"
            case .jsonDecodingFailed(let path, let message):
                return "Failed to decode package JSON at \(path): \(message)"
            case .timeout(let path, let seconds):
                return "Timed out after \(seconds)s loading package at \(path)"
            }
        }
    }
}
