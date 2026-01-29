import Foundation

/// Scans a directory for Swift packages and loads their descriptions
struct PackageScanner {
    let rootDirectory: URL
    let verbose: Bool

    /// Timeout for each package describe operation (in seconds)
    private let timeoutSeconds: UInt64 = 30

    /// Underlying loader for package descriptions
    private let loader: PackageDescriptionLoader

    /// Name of the cache file stored next to each Package.swift
    static let cacheFileName = PackageDescriptionLoader.cacheFileName

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
        self.loader = PackageDescriptionLoader(verbose: verbose, timeoutSeconds: 30)
    }

    /// Find all Package.swift files in the directory tree
    func findPackages() throws -> [URL] {
        var packages: [URL] = []
        let fileManager = FileManager.default

        // Check if the root directory itself is a package
        let rootPackageSwift = rootDirectory.appendingPathComponent("Package.swift")
        if fileManager.fileExists(atPath: rootPackageSwift.path) {
            packages.append(rootPackageSwift)
            if verbose {
                print("Found package: \(rootPackageSwift.path)")
            }
        }

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

    /// Load cached description if available and still valid (cache newer than Package.swift)
    func loadCachedDescription(at packagePath: URL) -> PackageDescription? {
        loader.loadCachedDescription(at: packagePath)
    }

    /// Write description to cache file
    func cacheDescription(_ description: PackageDescription, at packagePath: URL) throws {
        try loader.cacheDescription(description, at: packagePath)
    }

    /// Load package description, using cache if valid, otherwise running `swift package describe`
    /// Also runs `swift package dump-package` to get swiftSettings and merges the results
    func loadPackageDescription(at packagePath: URL) async throws -> PackageDescription {
        // Try cache first
        if let cached = loadCachedDescription(at: packagePath) {
            if verbose {
                print("Using cached description for: \(packagePath.deletingLastPathComponent().path)")
            }
            return cached
        }

        // Cache miss - load from swift package describe and dump-package in parallel
        async let describeTask = loader.loadPackageDescriptionFromSwift(at: packagePath)
        async let dumpTask = loadPackageDump(at: packagePath)

        let description = try await describeTask
        let dumpDescription = try? await dumpTask

        // Merge swiftSettings from dump into describe result
        let mergedDescription = mergeSwiftSettings(describe: description, dump: dumpDescription)

        // Cache the merged result
        do {
            try cacheDescription(mergedDescription, at: packagePath)
            if verbose {
                print("Cached description for: \(packagePath.deletingLastPathComponent().path)")
            }
        } catch {
            if verbose {
                print("Failed to cache description: \(error.localizedDescription)")
            }
        }

        return mergedDescription
    }

    /// Merge swiftSettings from dump-package into describe result
    private func mergeSwiftSettings(describe: PackageDescription, dump: DumpPackageDescription?) -> PackageDescription {
        guard let dump = dump else { return describe }

        // Build a lookup table of target name -> swift settings
        var settingsByTarget: [String: [SwiftSetting]] = [:]
        for dumpTarget in dump.targets {
            if let settings = dumpTarget.settings {
                let swiftSettings = settings.compactMap { $0.toSwiftSetting() }
                if !swiftSettings.isEmpty {
                    settingsByTarget[dumpTarget.name] = swiftSettings
                }
            }
        }

        // If no settings found, return original
        guard !settingsByTarget.isEmpty else { return describe }

        // Create new targets with swiftSettings merged in
        let mergedTargets = describe.targets.map { target -> PackageDescription.Target in
            var updatedTarget = target
            updatedTarget.swiftSettings = settingsByTarget[target.name]
            return updatedTarget
        }

        return PackageDescription(
            name: describe.name,
            manifestDisplayName: describe.manifestDisplayName,
            path: describe.path,
            platforms: describe.platforms,
            products: describe.products,
            targets: mergedTargets,
            dependencies: describe.dependencies,
            toolsVersion: describe.toolsVersion
        )
    }

    /// Load package dump using `swift package dump-package` with timeout
    private func loadPackageDump(at packagePath: URL) async throws -> DumpPackageDescription {
        let packageDirectory = packagePath.deletingLastPathComponent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "dump-package"]
        process.currentDirectoryURL = packageDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if verbose {
            print("Loading package dump: \(packageDirectory.path)")
        }

        // Create tasks to read output asynchronously
        let outputTask = Task {
            var data = Data()
            for try await chunk in outputPipe.fileHandleForReading.bytes {
                data.append(chunk)
            }
            return data
        }

        let errorTask = Task {
            var data = Data()
            for try await chunk in errorPipe.fileHandleForReading.bytes {
                data.append(chunk)
            }
            return data
        }

        try process.run()

        // Wait for process with timeout (using loader's helper)
        let completed = await loader.waitForProcessWithTimeout(process: process, timeoutSeconds: timeoutSeconds)

        if !completed {
            process.terminate()
            try? await Task.sleep(nanoseconds: 100_000_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            outputTask.cancel()
            errorTask.cancel()
            throw ScannerError.timeout(packageDirectory.path, timeoutSeconds)
        }

        let outputData = try await outputTask.value
        _ = try await errorTask.value

        if process.terminationStatus != 0 {
            throw ScannerError.packageDumpFailed(packageDirectory.path)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(DumpPackageDescription.self, from: outputData)
        } catch {
            throw ScannerError.jsonDecodingFailed(packageDirectory.path, error.localizedDescription)
        }
    }

    enum ScannerError: LocalizedError {
        case cannotEnumerateDirectory(String)
        case packageDumpFailed(String)
        case jsonDecodingFailed(String, String)
        case timeout(String, UInt64)

        var errorDescription: String? {
            switch self {
            case .cannotEnumerateDirectory(let path):
                return "Cannot enumerate directory: \(path)"
            case .packageDumpFailed(let path):
                return "Failed to dump package at \(path)"
            case .jsonDecodingFailed(let path, let message):
                return "Failed to decode package JSON at \(path): \(message)"
            case .timeout(let path, let seconds):
                return "Timed out after \(seconds)s loading package at \(path)"
            }
        }
    }
}
