import Foundation

/// Reusable utility for loading package descriptions from any Package.swift
/// Uses `swift package describe --type json` and supports caching
struct PackageDescriptionLoader {
    let verbose: Bool

    /// Timeout for each package describe operation (in seconds)
    private let timeoutSeconds: UInt64

    /// Name of the cache file stored next to each Package.swift
    static let cacheFileName = ".package-description.json"

    init(verbose: Bool = false, timeoutSeconds: UInt64 = 30) {
        self.verbose = verbose
        self.timeoutSeconds = timeoutSeconds
    }

    /// Load package description, using cache if valid, otherwise running `swift package describe`
    func loadPackageDescription(at packagePath: URL) async throws -> PackageDescription {
        // Try cache first
        if let cached = loadCachedDescription(at: packagePath) {
            if verbose {
                print("Using cached description for: \(packagePath.deletingLastPathComponent().path)")
            }
            return cached
        }

        // Cache miss - load from swift package describe
        let description = try await loadPackageDescriptionFromSwift(at: packagePath)

        // Cache the result
        do {
            try cacheDescription(description, at: packagePath)
            if verbose {
                print("Cached description for: \(packagePath.deletingLastPathComponent().path)")
            }
        } catch {
            if verbose {
                print("Failed to cache description: \(error.localizedDescription)")
            }
        }

        return description
    }

    /// Load cached description if available and still valid (cache newer than Package.swift)
    func loadCachedDescription(at packagePath: URL) -> PackageDescription? {
        let cacheFile = packagePath.deletingLastPathComponent()
            .appendingPathComponent(Self.cacheFileName)

        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheFile.path) else { return nil }

        // Check if cache is newer than Package.swift
        guard let pkgMod = try? fm.attributesOfItem(atPath: packagePath.path)[.modificationDate] as? Date,
              let cacheMod = try? fm.attributesOfItem(atPath: cacheFile.path)[.modificationDate] as? Date,
              cacheMod > pkgMod else { return nil }

        do {
            let data = try Data(contentsOf: cacheFile)
            return try JSONDecoder().decode(PackageDescription.self, from: data)
        } catch {
            if verbose {
                print("Cache read failed for \(packagePath.path): \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Write description to cache file
    func cacheDescription(_ description: PackageDescription, at packagePath: URL) throws {
        let cacheFile = packagePath.deletingLastPathComponent()
            .appendingPathComponent(Self.cacheFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(description)
        try data.write(to: cacheFile)
    }

    /// Load package description using `swift package describe --type json` with timeout
    func loadPackageDescriptionFromSwift(at packagePath: URL) async throws -> PackageDescription {
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

        // Create tasks to read output asynchronously
        let outputTask = Task {
            var data = Data()
            for try await chunk in outputPipe.fileHandleForReading.bytes {
                data.append(chunk)
                if verbose {
                    print(String(bytes: [chunk], encoding: .utf8) ?? "", terminator: "")
                }
            }
            return data
        }

        let errorTask = Task {
            var data = Data()
            for try await chunk in errorPipe.fileHandleForReading.bytes {
                data.append(chunk)
                if verbose {
                    print(String(bytes: [chunk], encoding: .utf8) ?? "", terminator: "")
                }
            }
            return data
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

            // Cancel reading tasks
            outputTask.cancel()
            errorTask.cancel()

            throw LoaderError.timeout(packageDirectory.path, timeoutSeconds)
        }

        // Wait for all output to be read
        let outputData = try await outputTask.value
        let errorData = try await errorTask.value

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw LoaderError.packageDescribeFailed(packageDirectory.path, errorMessage)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(PackageDescription.self, from: outputData)
        } catch {
            throw LoaderError.jsonDecodingFailed(packageDirectory.path, error.localizedDescription)
        }
    }

    /// Wait for a process to complete with a timeout (non-blocking polling)
    func waitForProcessWithTimeout(process: Process, timeoutSeconds: UInt64) async -> Bool {
        let pollIntervalNanoseconds: UInt64 = 100_000_000 // 100ms
        let maxPolls = (timeoutSeconds * 1_000_000_000) / pollIntervalNanoseconds

        for _ in 0..<maxPolls {
            if !process.isRunning {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        // Final check
        return !process.isRunning
    }

    enum LoaderError: LocalizedError {
        case packageDescribeFailed(String, String)
        case jsonDecodingFailed(String, String)
        case timeout(String, UInt64)

        var errorDescription: String? {
            switch self {
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
