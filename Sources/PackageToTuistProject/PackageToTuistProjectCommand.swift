import ArgumentParser

@main
struct PackageToTuistProject: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PackageToTuistProject",
        abstract: "Convert Swift Package.swift files to Tuist Project.swift files",
        version: "1.0.0"
    )

    @Argument(help: "Root directory containing Swift packages")
    var rootDirectory: String = "."

    @Option(name: .long, help: "Bundle ID prefix for generated targets")
    var bundleIdPrefix: String = "com.example"

    @Option(name: .long, help: "Default product type (staticFramework, framework, staticLibrary)")
    var productType: String = "staticFramework"

    @Option(name: .long, help: "Path to Tuist directory for dependency validation")
    var tuistDir: String? = nil

    @Flag(name: .long, help: "Preview changes without writing files")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Regenerate all Project.swift files, ignoring timestamps")
    var force: Bool = false

    func run() async throws {
        let command = ConvertCommand(
            rootDirectory: rootDirectory,
            bundleIdPrefix: bundleIdPrefix,
            productType: productType,
            tuistDir: tuistDir,
            dryRun: dryRun,
            verbose: verbose,
            force: force
        )
        try await command.execute()
    }
}
