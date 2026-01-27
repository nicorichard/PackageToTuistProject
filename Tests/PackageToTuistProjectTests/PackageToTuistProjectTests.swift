import Testing
import Foundation
@testable import PackageToTuistProject

// MARK: - LoadingProgress Tests

@Suite("LoadingProgress")
struct LoadingProgressTests {
    @Test("initializes with correct total")
    func initializesWithTotal() async {
        let progress = LoadingProgress(total: 10)
        let completed = await progress.getCompleted()
        let total = await progress.total

        #expect(completed == 0)
        #expect(total == 10)
    }

    @Test("increment increases completed count")
    func incrementIncreasesCount() async {
        let progress = LoadingProgress(total: 5)

        await progress.increment(packageName: "Package1")
        var completed = await progress.getCompleted()
        #expect(completed == 1)

        await progress.increment(packageName: "Package2")
        completed = await progress.getCompleted()
        #expect(completed == 2)
    }

    @Test("incrementFailed increases completed count")
    func incrementFailedIncreasesCount() async {
        let progress = LoadingProgress(total: 5)

        await progress.incrementFailed(path: "FailedPackage", error: "Some error")
        let completed = await progress.getCompleted()
        #expect(completed == 1)
    }

    @Test("handles concurrent increments correctly")
    func handlesConcurrentIncrements() async {
        let progress = LoadingProgress(total: 100)

        // Run 100 concurrent increments
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await progress.increment(packageName: "Package\(i)")
                }
            }
        }

        let completed = await progress.getCompleted()
        #expect(completed == 100)
    }

    @Test("mixed increment and incrementFailed works correctly")
    func mixedIncrements() async {
        let progress = LoadingProgress(total: 10)

        await progress.increment(packageName: "Success1")
        await progress.incrementFailed(path: "Failed1", error: "Error")
        await progress.increment(packageName: "Success2")
        await progress.incrementFailed(path: "Failed2", error: "Error")

        let completed = await progress.getCompleted()
        #expect(completed == 4)
    }
}

// MARK: - ConvertCommand Tests

@Suite("ConvertCommand")
struct ConvertCommandTests {
    @Test("initializes with correct properties")
    func initializesCorrectly() {
        let command = ConvertCommand(
            rootDirectory: "/path/to/root",
            bundleIdPrefix: "com.example",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: true,
            verbose: false
        )

        #expect(command.rootDirectory == "/path/to/root")
        #expect(command.bundleIdPrefix == "com.example")
        #expect(command.productType == "staticFramework")
        #expect(command.tuistDir == nil)
        #expect(command.dryRun == true)
        #expect(command.verbose == false)
        #expect(command.force == false)  // Default value
    }

    @Test("initializes with custom tuist directory")
    func initializesWithTuistDir() {
        let command = ConvertCommand(
            rootDirectory: "/path/to/root",
            bundleIdPrefix: "com.example",
            productType: "framework",
            tuistDir: "/custom/tuist",
            dryRun: false,
            verbose: true
        )

        #expect(command.tuistDir == "/custom/tuist")
        #expect(command.verbose == true)
    }
}

// MARK: - Parallel Loading Behavior Tests

@Suite("ParallelLoadingBehavior")
struct ParallelLoadingBehaviorTests {
    @Test("TaskGroup processes all items")
    func taskGroupProcessesAllItems() async {
        // Simulate the parallel loading pattern used in ConvertCommand
        let items = Array(0..<20)
        let maxConcurrent = 8

        actor ResultCollector {
            var results: [Int] = []
            func append(_ value: Int) { results.append(value) }
            func getResults() -> [Int] { return results }
        }

        let collector = ResultCollector()

        await withTaskGroup(of: Int.self) { group in
            var inFlight = 0
            var iterator = items.makeIterator()

            // Start initial batch
            while inFlight < maxConcurrent, let item = iterator.next() {
                group.addTask {
                    // Simulate async work
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    return item * 2
                }
                inFlight += 1
            }

            // Process results and add new tasks
            for await result in group {
                await collector.append(result)

                if let item = iterator.next() {
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 1_000_000)
                        return item * 2
                    }
                }
            }
        }

        let results = await collector.getResults()
        #expect(results.count == 20)
        // Check all expected results are present (order may vary due to concurrency)
        let expectedResults = Set(items.map { $0 * 2 })
        let actualResults = Set(results)
        #expect(actualResults == expectedResults)
    }

    @Test("TaskGroup handles failures gracefully")
    func taskGroupHandlesFailures() async {
        let items = Array(0..<10)

        actor Counter {
            var successCount = 0
            var failureCount = 0
            func incrementSuccess() { successCount += 1 }
            func incrementFailure() { failureCount += 1 }
            func getCounts() -> (success: Int, failure: Int) {
                return (successCount, failureCount)
            }
        }

        let counter = Counter()

        await withTaskGroup(of: Bool.self) { group in
            for item in items {
                group.addTask {
                    // Simulate some failures (odd numbers fail)
                    return item % 2 == 0
                }
            }

            for await success in group {
                if success {
                    await counter.incrementSuccess()
                } else {
                    await counter.incrementFailure()
                }
            }
        }

        let counts = await counter.getCounts()
        #expect(counts.success == 5) // 0, 2, 4, 6, 8
        #expect(counts.failure == 5) // 1, 3, 5, 7, 9
    }

    @Test("concurrency limit is respected")
    func concurrencyLimitRespected() async {
        let maxConcurrent = 4
        let totalTasks = 20

        actor ConcurrencyTracker {
            var currentConcurrency = 0
            var maxObservedConcurrency = 0

            func taskStarted() {
                currentConcurrency += 1
                if currentConcurrency > maxObservedConcurrency {
                    maxObservedConcurrency = currentConcurrency
                }
            }

            func taskEnded() {
                currentConcurrency -= 1
            }

            func getMaxObserved() -> Int {
                return maxObservedConcurrency
            }
        }

        let tracker = ConcurrencyTracker()
        let items = Array(0..<totalTasks)

        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0
            var iterator = items.makeIterator()

            while inFlight < maxConcurrent, iterator.next() != nil {
                group.addTask {
                    await tracker.taskStarted()
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    await tracker.taskEnded()
                }
                inFlight += 1
            }

            for await _ in group {
                if iterator.next() != nil {
                    group.addTask {
                        await tracker.taskStarted()
                        try? await Task.sleep(nanoseconds: 10_000_000)
                        await tracker.taskEnded()
                    }
                }
            }
        }

        let maxObserved = await tracker.getMaxObserved()
        #expect(maxObserved <= maxConcurrent)
    }
}

// MARK: - TuistDependency Tests

@Suite("TuistDependency")
struct TuistDependencyTests {
    @Test("target dependency generates correct Swift code")
    func targetDependencySwiftCode() {
        let dep = TuistDependency.target(name: "MyTarget")
        #expect(dep.swiftCode == ".target(name: \"MyTarget\")")
    }

    @Test("project dependency generates correct Swift code")
    func projectDependencySwiftCode() {
        let dep = TuistDependency.project(path: "../OtherProject", target: "OtherTarget")
        #expect(dep.swiftCode == ".project(target: \"OtherTarget\", path: \"../OtherProject\")")
    }

    @Test("external dependency generates correct Swift code")
    func externalDependencySwiftCode() {
        let dep = TuistDependency.external(name: "Alamofire")
        #expect(dep.swiftCode == ".external(name: \"Alamofire\")")
    }

    @Test("TuistDependency conforms to Equatable")
    func equatable() {
        let dep1 = TuistDependency.target(name: "A")
        let dep2 = TuistDependency.target(name: "A")
        let dep3 = TuistDependency.target(name: "B")

        #expect(dep1 == dep2)
        #expect(dep1 != dep3)
    }

    @Test("TuistDependency conforms to Hashable")
    func hashable() {
        let dep1 = TuistDependency.external(name: "Test")
        let dep2 = TuistDependency.external(name: "Test")

        var set = Set<TuistDependency>()
        set.insert(dep1)
        set.insert(dep2)

        #expect(set.count == 1)
    }
}

// MARK: - TuistTarget.ProductType Tests

@Suite("TuistTarget.ProductType")
struct ProductTypeTests {
    @Test("staticFramework generates correct Swift code")
    func staticFramework() {
        let type = TuistTarget.ProductType.staticFramework
        #expect(type.swiftCode == ".staticFramework")
    }

    @Test("framework generates correct Swift code")
    func framework() {
        let type = TuistTarget.ProductType.framework
        #expect(type.swiftCode == ".framework")
    }

    @Test("staticLibrary generates correct Swift code")
    func staticLibrary() {
        let type = TuistTarget.ProductType.staticLibrary
        #expect(type.swiftCode == ".staticLibrary")
    }

    @Test("unitTests generates correct Swift code")
    func unitTests() {
        let type = TuistTarget.ProductType.unitTests
        #expect(type.swiftCode == ".unitTests")
    }

    @Test("raw values are correct")
    func rawValues() {
        #expect(TuistTarget.ProductType.staticFramework.rawValue == "staticFramework")
        #expect(TuistTarget.ProductType.framework.rawValue == "framework")
        #expect(TuistTarget.ProductType.staticLibrary.rawValue == "staticLibrary")
        #expect(TuistTarget.ProductType.unitTests.rawValue == "unitTests")
    }
}

// MARK: - DependencyRequirement Tests

@Suite("DependencyRequirement")
struct DependencyRequirementTests {
    @Test("range requirement generates from version")
    func rangeRequirement() {
        let req = ExternalDependency.DependencyRequirement.range(from: "1.0.0", to: "2.0.0")
        #expect(req.swiftCode == "from: \"1.0.0\"")
    }

    @Test("exact requirement generates exact version")
    func exactRequirement() {
        let req = ExternalDependency.DependencyRequirement.exact("1.2.3")
        #expect(req.swiftCode == "exact: \"1.2.3\"")
    }

    @Test("branch requirement generates branch")
    func branchRequirement() {
        let req = ExternalDependency.DependencyRequirement.branch("main")
        #expect(req.swiftCode == "branch: \"main\"")
    }

    @Test("revision requirement generates revision")
    func revisionRequirement() {
        let req = ExternalDependency.DependencyRequirement.revision("abc123")
        #expect(req.swiftCode == "revision: \"abc123\"")
    }
}

// MARK: - DependencyCollector Tests

@Suite("DependencyCollector")
struct DependencyCollectorTests {
    @Test("registers local packages correctly")
    func registerLocalPackage() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [
                (name: "MyProduct", targets: ["MyTarget"]),
                (name: "AnotherProduct", targets: ["AnotherTarget"])
            ]
        )

        #expect(collector.isLocalPackage(identity: "MyPackage"))
        #expect(collector.isLocalPackage(identity: "mypackage")) // Case insensitive
        #expect(collector.localPackagePath(for: "MyPackage") == "../MyPackage")
    }

    @Test("registers external dependencies correctly")
    func registerExternalDependency() {
        var collector = DependencyCollector()
        let dep = ExternalDependency(
            identity: "Alamofire",
            url: "https://github.com/Alamofire/Alamofire",
            requirement: .range(from: "5.0.0", to: "6.0.0")
        )

        collector.registerExternalDependency(dep)

        let allDeps = collector.allExternalDependencies()
        #expect(allDeps.count == 1)
        #expect(allDeps[0].identity == "Alamofire")
    }

    @Test("keeps first registered external dependency on duplicate")
    func duplicateExternalDependency() {
        var collector = DependencyCollector()
        let dep1 = ExternalDependency(
            identity: "Package",
            url: "https://example.com/Package",
            requirement: .exact("1.0.0")
        )
        let dep2 = ExternalDependency(
            identity: "package", // Same identity, different case
            url: "https://example.com/Package",
            requirement: .exact("2.0.0")
        )

        collector.registerExternalDependency(dep1)
        collector.registerExternalDependency(dep2)

        let allDeps = collector.allExternalDependencies()
        #expect(allDeps.count == 1)
        #expect(allDeps[0].requirement == .exact("1.0.0"))
    }

    @Test("returns external dependencies sorted by identity")
    func sortedExternalDependencies() {
        var collector = DependencyCollector()
        collector.registerExternalDependency(ExternalDependency(
            identity: "Zebra",
            url: "https://example.com/Zebra",
            requirement: .exact("1.0.0")
        ))
        collector.registerExternalDependency(ExternalDependency(
            identity: "Apple",
            url: "https://example.com/Apple",
            requirement: .exact("1.0.0")
        ))

        let allDeps = collector.allExternalDependencies()
        #expect(allDeps[0].identity == "Apple")
        #expect(allDeps[1].identity == "Zebra")
    }

    @Test("package identity lookup is case insensitive")
    func caseInsensitiveLookup() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [(name: "MyProduct", targets: ["MyTarget"])]
        )

        #expect(collector.isLocalPackage(identity: "MYPACKAGE"))
        #expect(collector.isLocalPackage(identity: "mypackage"))
        #expect(collector.isLocalPackage(identity: "MyPackage"))
        #expect(collector.localPackagePath(for: "MYPACKAGE") == "../MyPackage")
    }

    @Test("packageIdentity(forProduct:) returns correct package")
    func packageIdentityForProduct() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [
                (name: "ProductA", targets: ["TargetA"]),
                (name: "ProductB", targets: ["TargetB"])
            ]
        )

        #expect(collector.packageIdentity(forProduct: "ProductA") == "MyPackage")
        #expect(collector.packageIdentity(forProduct: "ProductB") == "MyPackage")
        #expect(collector.packageIdentity(forProduct: "Unknown") == nil)
    }

    @Test("classifyDependency returns target for same-package dependencies")
    func classifyTargetDependency() {
        let collector = DependencyCollector()

        let result = collector.classifyDependency(
            productName: "MyTarget",
            currentPackagePath: URL(fileURLWithPath: "/path/to/package"),
            targetDependencies: ["MyTarget", "OtherTarget"],
            descriptions: [:]
        )

        #expect(result == .target(name: "MyTarget"))
    }

    @Test("classifyDependency returns external for unknown products")
    func classifyExternalDependency() {
        let collector = DependencyCollector()

        let result = collector.classifyDependency(
            productName: "Alamofire",
            currentPackagePath: URL(fileURLWithPath: "/path/to/package"),
            targetDependencies: [],
            descriptions: [:]
        )

        #expect(result == .external(name: "Alamofire"))
    }

    @Test("classifyDependency returns project for local package products")
    func classifyProjectDependency() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "OtherPackage",
            relativePath: "../OtherPackage",
            products: [(name: "OtherProduct", targets: ["OtherTarget"])]
        )

        let result = collector.classifyDependency(
            productName: "OtherProduct",
            currentPackagePath: URL(fileURLWithPath: "/path/to/package"),
            targetDependencies: [],
            descriptions: [:]
        )

        #expect(result == .project(path: "../OtherPackage", target: "OtherProduct"))
    }

    @Test("targets(forProduct:) returns correct targets for single-target product")
    func targetsForProductSingleTarget() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [(name: "MyProduct", targets: ["MyTarget"])]
        )

        let targets = collector.targets(forProduct: "MyProduct")
        #expect(targets == ["MyTarget"])
    }

    @Test("targets(forProduct:) returns correct targets for multi-target product")
    func targetsForProductMultiTarget() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [(name: "MyProduct", targets: ["TargetA", "TargetB", "TargetC"])]
        )

        let targets = collector.targets(forProduct: "MyProduct")
        #expect(targets == ["TargetA", "TargetB", "TargetC"])
    }

    @Test("targets(forProduct:) returns nil for unknown product")
    func targetsForProductUnknown() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [(name: "MyProduct", targets: ["MyTarget"])]
        )

        let targets = collector.targets(forProduct: "UnknownProduct")
        #expect(targets == nil)
    }

    @Test("handles multiple products with different target counts")
    func multipleProductsWithDifferentTargets() {
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "MyPackage",
            relativePath: "../MyPackage",
            products: [
                (name: "ProductA", targets: ["TargetA"]),
                (name: "ProductB", targets: ["TargetB1", "TargetB2"]),
                (name: "ProductC", targets: ["TargetC1", "TargetC2", "TargetC3"])
            ]
        )

        #expect(collector.targets(forProduct: "ProductA") == ["TargetA"])
        #expect(collector.targets(forProduct: "ProductB") == ["TargetB1", "TargetB2"])
        #expect(collector.targets(forProduct: "ProductC") == ["TargetC1", "TargetC2", "TargetC3"])
        #expect(collector.packageIdentity(forProduct: "ProductA") == "MyPackage")
        #expect(collector.packageIdentity(forProduct: "ProductB") == "MyPackage")
        #expect(collector.packageIdentity(forProduct: "ProductC") == "MyPackage")
    }
}

// MARK: - PackageDescription JSON Parsing Tests

@Suite("PackageDescription")
struct PackageDescriptionTests {
    @Test("decodes minimal package JSON")
    func decodeMinimalPackage() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path/to/package",
            "products": [],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.name == "TestPackage")
        #expect(package.path == "/path/to/package")
        #expect(package.products.isEmpty)
        #expect(package.targets.isEmpty)
        #expect(package.platforms == nil)
        #expect(package.dependencies == nil)
    }

    @Test("decodes package with platforms")
    func decodeWithPlatforms() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "platforms": [
                {"name": "ios", "version": "15.0"},
                {"name": "macos", "version": "12.0"}
            ],
            "products": [],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.platforms?.count == 2)
        #expect(package.platforms?[0].name == "ios")
        #expect(package.platforms?[0].version == "15.0")
    }

    @Test("decodes product with library type")
    func decodeLibraryProduct() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [
                {
                    "name": "MyLibrary",
                    "targets": ["MyTarget"],
                    "type": {"library": ["automatic"]}
                }
            ],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.products.count == 1)
        #expect(package.products[0].name == "MyLibrary")
        #expect(package.products[0].type.library != nil)
        #expect(package.products[0].type.executable == nil)
    }

    @Test("decodes product with executable type")
    func decodeExecutableProduct() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [
                {
                    "name": "MyTool",
                    "targets": ["MyTarget"],
                    "type": {"executable": null}
                }
            ],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.products.count == 1)
        #expect(package.products[0].name == "MyTool")
        #expect(package.products[0].type.executable == true)
    }

    @Test("decodes target with dependencies")
    func decodeTargetWithDependencies() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": [
                {
                    "name": "MyTarget",
                    "type": "library",
                    "path": "Sources/MyTarget",
                    "target_dependencies": ["OtherTarget"],
                    "product_dependencies": ["Alamofire"]
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.targets.count == 1)
        #expect(package.targets[0].name == "MyTarget")
        #expect(package.targets[0].type == "library")
        #expect(package.targets[0].path == "Sources/MyTarget")
        #expect(package.targets[0].targetDependencies == ["OtherTarget"])
        #expect(package.targets[0].productDependencies == ["Alamofire"])
    }

    @Test("decodes target with resources")
    func decodeTargetWithResources() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": [
                {
                    "name": "MyTarget",
                    "type": "library",
                    "path": "Sources/MyTarget",
                    "resources": [
                        {"path": "Resources/image.png", "rule": {"process": {}}},
                        {"path": "Resources/data.json", "rule": {"copy": {}}}
                    ]
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.targets[0].resources?.count == 2)
        #expect(package.targets[0].resources?[0].path == "Resources/image.png")
        #expect(package.targets[0].resources?[0].rule.process != nil)
        #expect(package.targets[0].resources?[1].rule.copy != nil)
    }

    @Test("decodes package dependencies with URL")
    func decodeURLDependency() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": [],
            "dependencies": [
                {
                    "identity": "alamofire",
                    "type": "sourceControl",
                    "url": "https://github.com/Alamofire/Alamofire",
                    "requirement": {
                        "range": [{"lower_bound": "5.0.0", "upper_bound": "6.0.0"}]
                    }
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.dependencies?.count == 1)
        #expect(package.dependencies?[0].identity == "alamofire")
        #expect(package.dependencies?[0].type == "sourceControl")
        #expect(package.dependencies?[0].url == "https://github.com/Alamofire/Alamofire")
        #expect(package.dependencies?[0].requirement?.range?[0].lowerBound == "5.0.0")
    }

    @Test("decodes local file system dependency")
    func decodeFileSystemDependency() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": [],
            "dependencies": [
                {
                    "identity": "localpackage",
                    "type": "fileSystem",
                    "path": "../LocalPackage"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.dependencies?[0].type == "fileSystem")
        #expect(package.dependencies?[0].path == "../LocalPackage")
    }

    @Test("decodes exact version requirement")
    func decodeExactRequirement() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": [],
            "dependencies": [
                {
                    "identity": "package",
                    "type": "sourceControl",
                    "url": "https://example.com/Package",
                    "requirement": {"exact": ["1.2.3"]}
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.dependencies?[0].requirement?.exact == ["1.2.3"])
    }

    @Test("decodes branch requirement")
    func decodeBranchRequirement() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": [],
            "dependencies": [
                {
                    "identity": "package",
                    "type": "sourceControl",
                    "url": "https://example.com/Package",
                    "requirement": {"branch": ["main"]}
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.dependencies?[0].requirement?.branch == ["main"])
    }

    @Test("hasLibraryProduct returns true when package has library product")
    func hasLibraryProductTrue() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [
                {"name": "MyLibrary", "targets": ["MyTarget"], "type": {"library": ["automatic"]}}
            ],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.hasLibraryProduct == true)
    }

    @Test("hasLibraryProduct returns false when package has only executable products")
    func hasLibraryProductFalseForExecutable() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [
                {"name": "MyTool", "targets": ["MyTarget"], "type": {"executable": null}}
            ],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.hasLibraryProduct == false)
    }

    @Test("hasLibraryProduct returns false when package has no products")
    func hasLibraryProductFalseForEmpty() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.hasLibraryProduct == false)
    }

    @Test("hasLibraryProduct returns true when package has mixed products including library")
    func hasLibraryProductTrueForMixed() throws {
        let json = """
        {
            "name": "TestPackage",
            "path": "/path",
            "products": [
                {"name": "MyTool", "targets": ["ToolTarget"], "type": {"executable": null}},
                {"name": "MyLibrary", "targets": ["LibTarget"], "type": {"library": ["automatic"]}}
            ],
            "targets": []
        }
        """

        let data = json.data(using: .utf8)!
        let package = try JSONDecoder().decode(PackageDescription.self, from: data)

        #expect(package.hasLibraryProduct == true)
    }
}

// MARK: - PackageConverter Tests

@Suite("PackageConverter")
struct PackageConverterTests {
    @Test("converts simple package to Tuist project")
    func convertSimplePackage() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [{"name": "MyPackage", "targets": ["MyTarget"], "type": {"library": ["automatic"]}}],
            "targets": [
                {
                    "name": "MyTarget",
                    "type": "library",
                    "path": "Sources/MyTarget"
                }
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/MyPackage/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.name == "MyPackage")
        #expect(project.targets.count == 1)
        #expect(project.targets[0].name == "MyTarget")
        #expect(project.targets[0].bundleId == "com.example.MyTarget")
        #expect(project.targets[0].product == .staticFramework)
    }

    @Test("skips executable targets")
    func skipsExecutableTargets() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {"name": "MyLib", "type": "library", "path": "Sources/MyLib"},
                {"name": "MyTool", "type": "executable", "path": "Sources/MyTool"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets.count == 1)
        #expect(project.targets[0].name == "MyLib")
    }

    @Test("converts test targets to unitTests product type")
    func convertsTestTargets() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {"name": "MyLibTests", "type": "test", "path": "Tests/MyLibTests"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].product == .unitTests)
    }

    @Test("throws error when platforms is nil")
    func throwsOnMissingPlatforms() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "products": [],
            "targets": [
                {"name": "MyTarget", "type": "library", "path": "Sources/MyTarget"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        #expect(throws: PackageConversionError.self) {
            _ = try converter.convert(
                package: package,
                packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
                collector: collector,
                allDescriptions: [:]
            )
        }
    }

    @Test("throws error when platforms is empty array")
    func throwsOnEmptyPlatforms() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [],
            "products": [],
            "targets": [
                {"name": "MyTarget", "type": "library", "path": "Sources/MyTarget"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        #expect(throws: PackageConversionError.self) {
            _ = try converter.convert(
                package: package,
                packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
                collector: collector,
                allDescriptions: [:]
            )
        }
    }

    @Test("error message contains package name and guidance")
    func errorMessageIsHelpful() throws {
        let error = PackageConversionError.missingPlatforms(package: "TestPackage")
        let description = error.description

        #expect(description.contains("TestPackage"))
        #expect(description.contains("platforms"))
        #expect(description.contains(".iOS"))
        #expect(description.contains(".macOS"))
    }

    @Test("uses correct destination for macOS platform")
    func macOSDestination() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "macos", "version": "12.0"}],
            "products": [],
            "targets": [
                {"name": "MyTarget", "type": "library", "path": "Sources/MyTarget"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].destinations == ".macOS")
    }

    @Test("converts target dependencies correctly")
    func convertsTargetDependencies() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {"name": "TargetA", "type": "library", "path": "Sources/TargetA"},
                {"name": "TargetB", "type": "library", "path": "Sources/TargetB", "target_dependencies": ["TargetA"]}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        let targetB = project.targets.first { $0.name == "TargetB" }!
        #expect(targetB.dependencies.count == 1)
        #expect(targetB.dependencies[0] == .target(name: "TargetA"))
    }

    @Test("converts external product dependencies correctly")
    func convertsExternalDependencies() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {"name": "MyTarget", "type": "library", "path": "Sources/MyTarget", "product_dependencies": ["Alamofire"]}
            ],
            "dependencies": [
                {"identity": "alamofire", "type": "sourceControl", "url": "https://github.com/Alamofire/Alamofire"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].dependencies.count == 1)
        #expect(project.targets[0].dependencies[0] == .external(name: "Alamofire"))
    }

    @Test("respects different product types")
    func respectsProductType() throws {
        let frameworkConverter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "framework"
        )

        let staticLibConverter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticLibrary"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {"name": "MyTarget", "type": "library", "path": "Sources/MyTarget"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let frameworkProject = try frameworkConverter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        let staticLibProject = try staticLibConverter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        #expect(frameworkProject.targets[0].product == .framework)
        #expect(staticLibProject.targets[0].product == .staticLibrary)
    }

    @Test("resolves multi-target product dependency to individual target dependencies")
    func convertsMultiTargetProductDependency() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        // Package that depends on a multi-target product from another package
        let packageJSON = """
        {
            "name": "ConsumerPackage",
            "path": "/path/to/ConsumerPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {
                    "name": "ConsumerTarget",
                    "type": "library",
                    "path": "Sources/ConsumerTarget",
                    "product_dependencies": ["MultiTargetLib"]
                }
            ],
            "dependencies": [
                {"identity": "providerpackage", "type": "fileSystem", "path": "../ProviderPackage"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        // Set up collector with a product that has multiple targets
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "ProviderPackage",
            relativePath: "../ProviderPackage",
            products: [(name: "MultiTargetLib", targets: ["TargetA", "TargetB"])]
        )

        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/ConsumerPackage/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        // Should have dependencies on both targets from the product
        let consumerTarget = project.targets.first { $0.name == "ConsumerTarget" }!
        #expect(consumerTarget.dependencies.count == 2)
        #expect(consumerTarget.dependencies.contains(.project(path: "../ProviderPackage", target: "TargetA")))
        #expect(consumerTarget.dependencies.contains(.project(path: "../ProviderPackage", target: "TargetB")))
    }

    @Test("handles multiple products with different target counts correctly")
    func convertsMultipleProductsWithVariousTargets() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "ConsumerPackage",
            "path": "/path/to/ConsumerPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {
                    "name": "ConsumerTarget",
                    "type": "library",
                    "path": "Sources/ConsumerTarget",
                    "product_dependencies": ["SingleTargetLib", "MultiTargetLib"]
                }
            ],
            "dependencies": [
                {"identity": "providerpackage", "type": "fileSystem", "path": "../ProviderPackage"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "ProviderPackage",
            relativePath: "../ProviderPackage",
            products: [
                (name: "SingleTargetLib", targets: ["SingleTarget"]),
                (name: "MultiTargetLib", targets: ["TargetA", "TargetB", "TargetC"])
            ]
        )

        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/ConsumerPackage/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        // Should have 1 + 3 = 4 dependencies
        let consumerTarget = project.targets.first { $0.name == "ConsumerTarget" }!
        #expect(consumerTarget.dependencies.count == 4)
        #expect(consumerTarget.dependencies.contains(.project(path: "../ProviderPackage", target: "SingleTarget")))
        #expect(consumerTarget.dependencies.contains(.project(path: "../ProviderPackage", target: "TargetA")))
        #expect(consumerTarget.dependencies.contains(.project(path: "../ProviderPackage", target: "TargetB")))
        #expect(consumerTarget.dependencies.contains(.project(path: "../ProviderPackage", target: "TargetC")))
    }

    @Test("deduplicates dependencies when products share targets")
    func deduplicatesSharedTargets() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        // Package that depends on two products that share a common target
        // CoreLib -> [Core, Utils]
        // NetworkLib -> [Network, Utils]
        // Both share "Utils" target
        let packageJSON = """
        {
            "name": "ConsumerPackage",
            "path": "/path/to/ConsumerPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {
                    "name": "ConsumerTarget",
                    "type": "library",
                    "path": "Sources/ConsumerTarget",
                    "product_dependencies": ["CoreLib", "NetworkLib"]
                }
            ],
            "dependencies": [
                {"identity": "networkstack", "type": "fileSystem", "path": "../NetworkStack"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        // Set up collector with two products that share the "Utils" target
        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "NetworkStack",
            relativePath: "../NetworkStack",
            products: [
                (name: "CoreLib", targets: ["Core", "Utils"]),
                (name: "NetworkLib", targets: ["Network", "Utils"])
            ]
        )

        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/ConsumerPackage/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        // Should have 3 unique dependencies: Core, Utils, Network (Utils deduplicated)
        let consumerTarget = project.targets.first { $0.name == "ConsumerTarget" }!
        #expect(consumerTarget.dependencies.count == 3)
        #expect(consumerTarget.dependencies.contains(.project(path: "../NetworkStack", target: "Core")))
        #expect(consumerTarget.dependencies.contains(.project(path: "../NetworkStack", target: "Utils")))
        #expect(consumerTarget.dependencies.contains(.project(path: "../NetworkStack", target: "Network")))

        // Verify order is preserved (Core, Utils from CoreLib, then Network from NetworkLib)
        #expect(consumerTarget.dependencies[0] == .project(path: "../NetworkStack", target: "Core"))
        #expect(consumerTarget.dependencies[1] == .project(path: "../NetworkStack", target: "Utils"))
        #expect(consumerTarget.dependencies[2] == .project(path: "../NetworkStack", target: "Network"))
    }

    @Test("single target product still works correctly")
    func convertsSingleTargetProductDependency() throws {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "ConsumerPackage",
            "path": "/path/to/ConsumerPackage",
            "platforms": [{"name": "ios", "version": "15.0"}],
            "products": [],
            "targets": [
                {
                    "name": "ConsumerTarget",
                    "type": "library",
                    "path": "Sources/ConsumerTarget",
                    "product_dependencies": ["SingleLib"]
                }
            ],
            "dependencies": [
                {"identity": "providerpackage", "type": "fileSystem", "path": "../ProviderPackage"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        var collector = DependencyCollector()
        collector.registerLocalPackage(
            identity: "ProviderPackage",
            relativePath: "../ProviderPackage",
            products: [(name: "SingleLib", targets: ["SingleTarget"])]
        )

        let project = try converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/ConsumerPackage/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        let consumerTarget = project.targets.first { $0.name == "ConsumerTarget" }!
        #expect(consumerTarget.dependencies.count == 1)
        #expect(consumerTarget.dependencies[0] == .project(path: "../ProviderPackage", target: "SingleTarget"))
    }
}

// MARK: - ProjectWriter Tests

@Suite("ProjectWriter")
struct ProjectWriterTests {
    @Test("generates Project.swift with correct structure")
    func generateBasicProject() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(output.contains("import ProjectDescription"))
        #expect(output.contains("let project = Project("))
        #expect(output.contains("name: \"MyProject\""))
        #expect(output.contains("targets: ["))
    }

    @Test("generates target with correct properties")
    func generateTarget() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .framework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [],
                    destinations: ".macOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(output.contains("name: \"MyTarget\""))
        #expect(output.contains("destinations: .macOS"))
        #expect(output.contains("product: .framework"))
        #expect(output.contains("bundleId: \"com.example.MyTarget\""))
        #expect(output.contains("sources: [\"Sources/MyTarget/**\"]"))
        // Check that SPM resource patterns are included
        #expect(output.contains("Sources/MyTarget/**/*.xcassets"))
        #expect(output.contains("Sources/MyTarget/**/*.xib"))
        #expect(output.contains("Sources/MyTarget/**/*.storyboard"))
        #expect(output.contains("Sources/MyTarget/**/*.xcdatamodeld"))
        #expect(output.contains("Sources/MyTarget/**/*.xcmappingmodel"))
        #expect(output.contains("Sources/MyTarget/**/*.lproj/**"))
        #expect(output.contains("Sources/MyTarget/**/*.metal"))
        #expect(output.contains("Sources/MyTarget/Resources/**"))
    }

    @Test("generates target with dependencies")
    func generateTargetWithDependencies() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [
                        .target(name: "OtherTarget"),
                        .external(name: "Alamofire"),
                        .project(path: "../Other", target: "OtherLib")
                    ],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(output.contains("dependencies: ["))
        #expect(output.contains(".target(name: \"OtherTarget\")"))
        #expect(output.contains(".external(name: \"Alamofire\")"))
        #expect(output.contains(".project(target: \"OtherLib\", path: \"../Other\")"))
    }

    @Test("generates multiple targets with commas")
    func generateMultipleTargets() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "Target1",
                    product: .staticFramework,
                    bundleId: "com.example.Target1",
                    sourcesPath: "Sources/Target1",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                ),
                TuistTarget(
                    name: "Target2",
                    product: .staticFramework,
                    bundleId: "com.example.Target2",
                    sourcesPath: "Sources/Target2",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(output.contains("Target1"))
        #expect(output.contains("Target2"))
        // Should have comma between targets - the output has ),\n between targets
        #expect(output.contains("),"))
    }

    @Test("omits dependencies section when empty")
    func omitEmptyDependencies() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should NOT contain dependencies key when empty
        #expect(!output.contains("dependencies:"))
    }

    @Test("includes ENABLE_TESTING_SEARCH_PATHS when needsTestingSearchPaths is true")
    func includesTestingSearchPathsSetting() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "TestHelpers",
                    product: .staticFramework,
                    bundleId: "com.example.TestHelpers",
                    sourcesPath: "Sources/TestHelpers",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: true
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(output.contains("\"ENABLE_TESTING_SEARCH_PATHS\": \"YES\""))
    }

    @Test("omits ENABLE_TESTING_SEARCH_PATHS when needsTestingSearchPaths is false")
    func omitsTestingSearchPathsSetting() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "RegularTarget",
                    product: .staticFramework,
                    bundleId: "com.example.RegularTarget",
                    sourcesPath: "Sources/RegularTarget",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(!output.contains("ENABLE_TESTING_SEARCH_PATHS"))
    }

    // MARK: - Comma Edge Case Tests

    @Test("target with no dependencies has valid comma placement")
    func noDependenciesValidCommas() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should not have double commas
        #expect(!output.contains(",,"))
        // Should not have missing commas before settings (check for valid pattern)
        #expect(output.contains("resources:"))
        #expect(output.contains("settings:"))
    }

    @Test("target with one dependency has valid comma placement")
    func oneDependencyValidCommas() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [.target(name: "OtherTarget")],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should not have double commas
        #expect(!output.contains(",,"))
        // Check resources and dependencies are both present
        #expect(output.contains("resources:"))
        #expect(output.contains("dependencies:"))
        #expect(output.contains("settings:"))
    }

    @Test("target with deploymentTargets has valid comma placement")
    func withDeploymentTargetsValidCommas() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: ".iOS(\"15.0\")",
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should not have double commas
        #expect(!output.contains(",,"))
        #expect(output.contains("deploymentTargets:"))
        #expect(output.contains("sources:"))
    }

    @Test("target without deploymentTargets has valid comma placement")
    func withoutDeploymentTargetsValidCommas() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "MyTarget",
                    product: .staticFramework,
                    bundleId: "com.example.MyTarget",
                    sourcesPath: "Sources/MyTarget",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should not have double commas
        #expect(!output.contains(",,"))
        #expect(!output.contains("deploymentTargets:"))
        #expect(output.contains("bundleId:"))
        #expect(output.contains("sources:"))
    }

    @Test("multiple targets have correct commas between them")
    func multipleTargetsValidCommas() {
        let writer = ProjectWriter()
        let project = TuistProject(
            name: "MyProject",
            path: "/path/to/project",
            targets: [
                TuistTarget(
                    name: "Target1",
                    product: .staticFramework,
                    bundleId: "com.example.Target1",
                    sourcesPath: "Sources/Target1",
                    dependencies: [],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: false
                ),
                TuistTarget(
                    name: "Target2",
                    product: .staticFramework,
                    bundleId: "com.example.Target2",
                    sourcesPath: "Sources/Target2",
                    dependencies: [.target(name: "Target1")],
                    destinations: ".iOS",
                    deploymentTargets: ".iOS(\"15.0\")",
                    packageName: "MyProject",
                    needsTestingSearchPaths: true
                ),
                TuistTarget(
                    name: "Target3",
                    product: .unitTests,
                    bundleId: "com.example.Target3",
                    sourcesPath: "Tests/Target3",
                    dependencies: [.target(name: "Target1"), .external(name: "Quick")],
                    destinations: ".iOS",
                    deploymentTargets: nil,
                    packageName: "MyProject",
                    needsTestingSearchPaths: true
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should not have double commas
        #expect(!output.contains(",,"))
        // Should have all three targets
        #expect(output.contains("Target1"))
        #expect(output.contains("Target2"))
        #expect(output.contains("Target3"))
        // Comma between closing parenthesis and next target
        // Count occurrences of ")," which should appear between targets
        let closingParenCommaCount = output.components(separatedBy: "),").count - 1
        // Should have at least 2 occurrences (between targets in the array)
        #expect(closingParenCommaCount >= 2)
    }

    @Test("generated output has no double commas in any configuration")
    func noDoubleCommasInAnyConfiguration() {
        let writer = ProjectWriter()

        // Test various configurations
        let configurations: [(deps: [TuistDependency], deployment: String?, testing: Bool)] = [
            ([], nil, false),
            ([], nil, true),
            ([], ".iOS(\"15.0\")", false),
            ([], ".iOS(\"15.0\")", true),
            ([.target(name: "A")], nil, false),
            ([.target(name: "A")], nil, true),
            ([.target(name: "A")], ".iOS(\"15.0\")", false),
            ([.target(name: "A")], ".iOS(\"15.0\")", true),
            ([.target(name: "A"), .external(name: "B")], nil, false),
            ([.target(name: "A"), .external(name: "B")], ".iOS(\"15.0\")", true),
        ]

        for config in configurations {
            let project = TuistProject(
                name: "TestProject",
                path: "/path",
                targets: [
                    TuistTarget(
                        name: "TestTarget",
                        product: .staticFramework,
                        bundleId: "com.test",
                        sourcesPath: "Sources/Test",
                        dependencies: config.deps,
                        destinations: ".iOS",
                        deploymentTargets: config.deployment,
                        packageName: "TestProject",
                        needsTestingSearchPaths: config.testing
                    )
                ]
            )

            let output = writer.generate(project: project)
            #expect(!output.contains(",,"), "Double comma found in config: deps=\(config.deps.count), deployment=\(config.deployment ?? "nil"), testing=\(config.testing)")
        }
    }
}

// MARK: - PackageScanner Tests

@Suite("PackageScanner")
struct PackageScannerTests {
    @Test("finds package when root directory itself is a package")
    func findsPackageAtRoot() throws {
        // Create a temporary directory that IS a package (contains Package.swift)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift at the root
        let packageSwiftURL = tempDir.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 5.9".write(to: packageSwiftURL, atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let packages = try scanner.findPackages()

        #expect(packages.count == 1)
        #expect(packages[0].lastPathComponent == "Package.swift")
        #expect(packages[0].deletingLastPathComponent().standardizedFileURL == tempDir.standardizedFileURL)
    }

    @Test("finds packages in subdirectories")
    func findsPackagesInSubdirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create two subdirectories with Package.swift files
        let package1Dir = tempDir.appendingPathComponent("Package1")
        let package2Dir = tempDir.appendingPathComponent("Package2")
        try FileManager.default.createDirectory(at: package1Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package2Dir, withIntermediateDirectories: true)

        try "// Package1".write(to: package1Dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "// Package2".write(to: package2Dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let packages = try scanner.findPackages()

        #expect(packages.count == 2)
        let packageNames = Set(packages.map { $0.deletingLastPathComponent().lastPathComponent })
        #expect(packageNames.contains("Package1"))
        #expect(packageNames.contains("Package2"))
    }

    @Test("finds both root package and subdirectory packages")
    func findsBothRootAndSubdirectoryPackages() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift at root
        try "// Root package".write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        // Create a subdirectory with Package.swift
        let subDir = tempDir.appendingPathComponent("SubPackage")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "// Sub package".write(to: subDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let packages = try scanner.findPackages()

        #expect(packages.count == 2)
    }

    @Test("excludes .build directory")
    func excludesBuildDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift at root
        try "// Root".write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        // Create .build directory with a Package.swift (should be ignored)
        let buildDir = tempDir.appendingPathComponent(".build").appendingPathComponent("checkouts").appendingPathComponent("SomePackage")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "// Should be ignored".write(to: buildDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let packages = try scanner.findPackages()

        #expect(packages.count == 1)
        #expect(packages[0].deletingLastPathComponent().standardizedFileURL == tempDir.standardizedFileURL)
    }

    @Test("returns empty array when no packages found")
    func returnsEmptyWhenNoPackages() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create some files but no Package.swift
        try "// Not a package".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let packages = try scanner.findPackages()

        #expect(packages.isEmpty)
    }

    @Test("cacheFileName returns expected value")
    func cacheFileNameReturnsExpectedValue() {
        #expect(PackageScanner.cacheFileName == ".package-description.json")
    }

    @Test("loadCachedDescription returns nil when cache file does not exist")
    func loadCachedDescriptionReturnsNilWhenCacheMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift but no cache file
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let cached = scanner.loadCachedDescription(at: packagePath)

        #expect(cached == nil)
    }

    @Test("loadCachedDescription returns nil when cache is older than Package.swift")
    func loadCachedDescriptionReturnsNilWhenCacheIsStale() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create cache file first (older)
        let cachePath = tempDir.appendingPathComponent(PackageScanner.cacheFileName)
        let cacheContent = """
        {"name":"TestPackage","path":"/test","products":[],"targets":[],"dependencies":null}
        """
        try cacheContent.write(to: cachePath, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.1)

        // Create Package.swift second (newer)
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let cached = scanner.loadCachedDescription(at: packagePath)

        #expect(cached == nil)
    }

    @Test("loadCachedDescription returns description when cache is newer than Package.swift")
    func loadCachedDescriptionReturnsCachedWhenValid() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift first (older)
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.1)

        // Create cache file second (newer)
        let cachePath = tempDir.appendingPathComponent(PackageScanner.cacheFileName)
        let cacheContent = """
        {"name":"CachedPackage","path":"/cached","products":[],"targets":[]}
        """
        try cacheContent.write(to: cachePath, atomically: true, encoding: .utf8)

        let scanner = PackageScanner(rootDirectory: tempDir)
        let cached = scanner.loadCachedDescription(at: packagePath)

        #expect(cached != nil)
        #expect(cached?.name == "CachedPackage")
    }

    @Test("cacheDescription writes valid JSON file")
    func cacheDescriptionWritesValidJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        // Create a minimal description to cache
        let description = PackageDescription(
            name: "TestPackage",
            manifestDisplayName: nil,
            path: tempDir.path,
            platforms: nil,
            products: [],
            targets: [],
            dependencies: nil,
            toolsVersion: "5.9"
        )

        let scanner = PackageScanner(rootDirectory: tempDir)
        try scanner.cacheDescription(description, at: packagePath)

        // Verify cache file was written
        let cachePath = tempDir.appendingPathComponent(PackageScanner.cacheFileName)
        #expect(FileManager.default.fileExists(atPath: cachePath.path))

        // Verify it can be read back
        let data = try Data(contentsOf: cachePath)
        let decoded = try JSONDecoder().decode(PackageDescription.self, from: data)
        #expect(decoded.name == "TestPackage")
        #expect(decoded.toolsVersion == "5.9")
    }

    @Test("cacheDescription and loadCachedDescription round trip")
    func cacheRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageScannerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.1)

        let original = PackageDescription(
            name: "RoundTripPackage",
            manifestDisplayName: "Round Trip",
            path: tempDir.path,
            platforms: [PackageDescription.Platform(name: "macos", version: "14.0")],
            products: [
                PackageDescription.Product(
                    name: "MyLib",
                    targets: ["MyTarget"],
                    type: PackageDescription.Product.ProductType(library: ["automatic"], executable: nil)
                )
            ],
            targets: [],
            dependencies: nil,
            toolsVersion: "5.9"
        )

        let scanner = PackageScanner(rootDirectory: tempDir)
        try scanner.cacheDescription(original, at: packagePath)

        let loaded = scanner.loadCachedDescription(at: packagePath)
        #expect(loaded != nil)
        #expect(loaded?.name == "RoundTripPackage")
        #expect(loaded?.manifestDisplayName == "Round Trip")
        #expect(loaded?.platforms?.count == 1)
        #expect(loaded?.products.count == 1)
        #expect(loaded?.hasLibraryProduct == true)
    }
}

// MARK: - ImportScanner Tests

@Suite("ImportScanner")
struct ImportScannerTests {
    @Test("detects import XCTest")
    func detectsXCTestImport() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
        import XCTest

        class MyTests: XCTestCase {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == true)
    }

    @Test("detects import Testing")
    func detectsTestingImport() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
        import Testing

        @Suite struct MyTests {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == true)
    }

    @Test("detects import StoreKitTest")
    func detectsStoreKitTestImport() {
        let scanner = ImportScanner()
        let content = """
        import StoreKit
        import StoreKitTest

        class StoreTests {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == true)
    }

    @Test("ignores single-line commented imports")
    func ignoresSingleLineCommentedImports() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
        // import XCTest
        // import Testing

        class NotATest {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == false)
    }

    @Test("ignores block commented imports")
    func ignoresBlockCommentedImports() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
        /* import XCTest */
        /*
        import Testing
        */

        class NotATest {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == false)
    }

    @Test("returns false when no testing imports present")
    func noTestingImports() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
        import UIKit

        class MyView: UIView {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == false)
    }

    @Test("handles empty file")
    func handlesEmptyFile() {
        let scanner = ImportScanner()
        #expect(scanner.containsTestingImport(fileContent: "") == false)
    }

    @Test("handles file with only whitespace and comments")
    func handlesWhitespaceOnlyFile() {
        let scanner = ImportScanner()
        let content = """
        // This is a comment
        /* Another comment */

        """

        #expect(scanner.containsTestingImport(fileContent: content) == false)
    }

    @Test("detects import even with leading whitespace")
    func detectsImportWithLeadingWhitespace() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
            import XCTest

        class MyTests {}
        """

        #expect(scanner.containsTestingImport(fileContent: content) == true)
    }

    @Test("does not match partial framework names")
    func doesNotMatchPartialNames() {
        let scanner = ImportScanner()
        let content = """
        import Foundation
        import XCTestExtensions
        import MyTesting
        import StoreKitTestHelper

        class MyClass {}
        """

        // These should not match because the import is for a different module
        // that happens to contain the framework name
        #expect(scanner.containsTestingImport(fileContent: content) == false)
    }
}

// MARK: - ExternalDependency Tests

@Suite("ExternalDependency")
struct ExternalDependencyTests {
    @Test("ExternalDependency conforms to Equatable")
    func equatable() {
        let dep1 = ExternalDependency(
            identity: "Package",
            url: "https://example.com/Package",
            requirement: .exact("1.0.0")
        )
        let dep2 = ExternalDependency(
            identity: "Package",
            url: "https://example.com/Package",
            requirement: .exact("1.0.0")
        )
        let dep3 = ExternalDependency(
            identity: "Package",
            url: "https://example.com/Package",
            requirement: .exact("2.0.0")
        )

        #expect(dep1 == dep2)
        #expect(dep1 != dep3)
    }

    @Test("ExternalDependency conforms to Hashable")
    func hashable() {
        let dep1 = ExternalDependency(
            identity: "Package",
            url: "https://example.com/Package",
            requirement: .branch("main")
        )
        let dep2 = ExternalDependency(
            identity: "Package",
            url: "https://example.com/Package",
            requirement: .branch("main")
        )

        var set = Set<ExternalDependency>()
        set.insert(dep1)
        set.insert(dep2)

        #expect(set.count == 1)
    }
}

// MARK: - Fixture Integration Tests

/// Helper to locate test fixtures
private func fixturesDirectory() -> URL {
    // Get the path to the test file, then navigate to Fixtures
    let testFileURL = URL(fileURLWithPath: #filePath)
    return testFileURL
        .deletingLastPathComponent()  // PackageToTuistProjectTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")
}

@Suite("FixtureIntegration")
struct FixtureIntegrationTests {
    @Test("loads BasicLibrary fixture")
    func loadBasicLibrary() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("BasicLibrary/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        #expect(description.name == "BasicLibrary")
        #expect(description.platforms?.count == 1)
        #expect(description.platforms?[0].name == "ios")
        #expect(description.platforms?[0].version == "15.0")
        #expect(description.products.count == 1)
        #expect(description.products[0].name == "BasicLibrary")
        #expect(description.products[0].type.library != nil)
        #expect(description.targets.count == 1)
        #expect(description.targets[0].name == "BasicLibrary")
        #expect(description.targets[0].type == "library")
    }

    @Test("loads MultiTarget fixture with dependencies")
    func loadMultiTarget() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("MultiTarget/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        #expect(description.name == "MultiTarget")
        #expect(description.products.count == 1)
        #expect(description.products[0].targets.count == 2)
        #expect(description.targets.count == 2)

        let coreTarget = description.targets.first { $0.name == "Core" }
        let featureTarget = description.targets.first { $0.name == "Feature" }

        #expect(coreTarget != nil)
        #expect(featureTarget != nil)
        #expect(featureTarget?.targetDependencies == ["Core"])
    }

    @Test("loads WithDependencies fixture with external dependency")
    func loadWithDependencies() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("WithDependencies/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        #expect(description.name == "WithDependencies")
        #expect(description.dependencies?.count == 1)
        #expect(description.dependencies?[0].identity == "swift-argument-parser")
        #expect(description.dependencies?[0].type == "sourceControl")
        #expect(description.targets[0].productDependencies == ["ArgumentParser"])
    }

    @Test("loads WithTestTarget fixture")
    func loadWithTestTarget() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("WithTestTarget/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        #expect(description.name == "WithTestTarget")
        #expect(description.products.count == 1)
        #expect(description.targets.count == 2)

        let libTarget = description.targets.first { $0.name == "MyLib" }
        let testTarget = description.targets.first { $0.name == "MyLibTests" }

        #expect(libTarget?.type == "library")
        #expect(testTarget?.type == "test")
        #expect(testTarget?.targetDependencies == ["MyLib"])
    }

    @Test("loads MultiPlatform fixture with multiple platforms")
    func loadMultiPlatform() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("MultiPlatform/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        #expect(description.name == "MultiPlatform")
        #expect(description.platforms?.count == 3)

        let platformNames = Set(description.platforms?.map { $0.name } ?? [])
        #expect(platformNames.contains("ios"))
        #expect(platformNames.contains("macos"))
        #expect(platformNames.contains("tvos"))
    }

    @Test("converts BasicLibrary fixture to Tuist project")
    func convertBasicLibrary() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("BasicLibrary/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        let converter = PackageConverter(
            bundleIdPrefix: "com.test",
            productType: "staticFramework"
        )

        let project = try converter.convert(
            package: description,
            packagePath: fixtureURL,
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        #expect(project.name == "BasicLibrary")
        #expect(project.targets.count == 1)
        #expect(project.targets[0].name == "BasicLibrary")
        #expect(project.targets[0].bundleId == "com.test.BasicLibrary")
        #expect(project.targets[0].product == .staticFramework)
        #expect(project.targets[0].destinations == ".iOS")
    }

    @Test("converts MultiTarget fixture preserving dependencies")
    func convertMultiTarget() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("MultiTarget/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        let converter = PackageConverter(
            bundleIdPrefix: "com.test",
            productType: "framework"
        )

        let project = try converter.convert(
            package: description,
            packagePath: fixtureURL,
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        #expect(project.name == "MultiTarget")
        #expect(project.targets.count == 2)

        let featureTarget = project.targets.first { $0.name == "Feature" }
        #expect(featureTarget?.dependencies.count == 1)
        #expect(featureTarget?.dependencies[0] == .target(name: "Core"))
    }

    @Test("converts WithTestTarget fixture with test target product type")
    func convertWithTestTarget() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("WithTestTarget/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        let converter = PackageConverter(
            bundleIdPrefix: "com.test",
            productType: "staticFramework"
        )

        let project = try converter.convert(
            package: description,
            packagePath: fixtureURL,
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        #expect(project.name == "WithTestTarget")

        let libTarget = project.targets.first { $0.name == "MyLib" }
        let testTarget = project.targets.first { $0.name == "MyLibTests" }

        #expect(libTarget?.product == .staticFramework)
        #expect(testTarget?.product == .unitTests)
        #expect(testTarget?.dependencies.contains(.target(name: "MyLib")) == true)
    }

    @Test("converts WithDependencies fixture with external dependencies")
    func convertWithDependencies() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("WithDependencies/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        let converter = PackageConverter(
            bundleIdPrefix: "com.test",
            productType: "staticFramework"
        )

        let project = try converter.convert(
            package: description,
            packagePath: fixtureURL,
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        #expect(project.name == "WithDependencies")
        #expect(project.targets[0].dependencies.contains(.external(name: "ArgumentParser")) == true)
    }

    @Test("generates valid Project.swift from BasicLibrary fixture")
    func generateProjectSwift() async throws {
        let fixtureURL = fixturesDirectory().appendingPathComponent("BasicLibrary/Package.swift")
        let scanner = PackageScanner(rootDirectory: fixtureURL.deletingLastPathComponent())
        let description = try await scanner.loadPackageDescription(at: fixtureURL)

        let converter = PackageConverter(
            bundleIdPrefix: "com.test",
            productType: "staticFramework"
        )

        let project = try converter.convert(
            package: description,
            packagePath: fixtureURL,
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        let writer = ProjectWriter()
        let output = writer.generate(project: project)

        #expect(output.contains("import ProjectDescription"))
        #expect(output.contains("let project = Project("))
        #expect(output.contains("name: \"BasicLibrary\""))
        #expect(output.contains("name: \"BasicLibrary\""))
        #expect(output.contains("destinations: .iOS"))
        #expect(output.contains("product: .staticFramework"))
        #expect(output.contains("bundleId: \"com.test.BasicLibrary\""))
        #expect(!output.contains(",,"))  // No double commas
    }
}

// MARK: - All-or-Nothing Cache Tests

@Suite("AllOrNothingCache")
struct AllOrNothingCacheTests {

    /// Helper to create a temporary directory with test files
    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Helper to clean up temp directory
    private func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("needsRegeneration returns true when Project.swift does not exist")
    func needsRegenerationReturnsTrueWhenProjectMissing() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        // Create Package.swift and cache file, but no Project.swift
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        let cachePath = tempDir.appendingPathComponent(PackageScanner.cacheFileName)
        try "{}".write(to: cachePath, atomically: true, encoding: .utf8)

        let command = ConvertCommand(
            rootDirectory: tempDir.path,
            bundleIdPrefix: "com.test",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: false,
            verbose: false,
            force: false
        )

        let needsRegen = command.needsRegeneration(packagePath: packagePath)
        #expect(needsRegen == true)
    }

    @Test("needsRegeneration returns true when cache file does not exist")
    func needsRegenerationReturnsTrueWhenCacheMissing() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        // Create Package.swift and Project.swift, but no cache file
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        let projectPath = tempDir.appendingPathComponent("Project.swift")
        try "// Project".write(to: projectPath, atomically: true, encoding: .utf8)

        let command = ConvertCommand(
            rootDirectory: tempDir.path,
            bundleIdPrefix: "com.test",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: false,
            verbose: false,
            force: false
        )

        let needsRegen = command.needsRegeneration(packagePath: packagePath)
        #expect(needsRegen == true)
    }

    @Test("needsRegeneration returns true when Project.swift is older than cache")
    func needsRegenerationReturnsTrueWhenProjectOlderThanCache() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        // Create Package.swift
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        // Create Project.swift first (older)
        let projectPath = tempDir.appendingPathComponent("Project.swift")
        try "// Project".write(to: projectPath, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.1)

        // Create cache file second (newer)
        let cachePath = tempDir.appendingPathComponent(PackageScanner.cacheFileName)
        try "{}".write(to: cachePath, atomically: true, encoding: .utf8)

        let command = ConvertCommand(
            rootDirectory: tempDir.path,
            bundleIdPrefix: "com.test",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: false,
            verbose: false,
            force: false
        )

        let needsRegen = command.needsRegeneration(packagePath: packagePath)
        #expect(needsRegen == true)
    }

    @Test("needsRegeneration returns false when Project.swift is newer than cache")
    func needsRegenerationReturnsFalseWhenProjectNewerThanCache() throws {
        let tempDir = try createTempDirectory()
        defer { cleanupTempDirectory(tempDir) }

        // Create Package.swift
        let packagePath = tempDir.appendingPathComponent("Package.swift")
        try "// Package".write(to: packagePath, atomically: true, encoding: .utf8)

        // Create cache file first (older)
        let cachePath = tempDir.appendingPathComponent(PackageScanner.cacheFileName)
        try "{}".write(to: cachePath, atomically: true, encoding: .utf8)

        Thread.sleep(forTimeInterval: 0.1)

        // Create Project.swift second (newer)
        let projectPath = tempDir.appendingPathComponent("Project.swift")
        try "// Project".write(to: projectPath, atomically: true, encoding: .utf8)

        let command = ConvertCommand(
            rootDirectory: tempDir.path,
            bundleIdPrefix: "com.test",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: false,
            verbose: false,
            force: false
        )

        let needsRegen = command.needsRegeneration(packagePath: packagePath)
        #expect(needsRegen == false)
    }

    @Test("ConvertCommand initializes with force flag")
    func initializesWithForceFlag() {
        let command = ConvertCommand(
            rootDirectory: "/path/to/root",
            bundleIdPrefix: "com.example",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: false,
            verbose: false,
            force: true
        )

        #expect(command.force == true)
    }

    @Test("ConvertCommand force defaults to false")
    func forceDefaultsToFalse() {
        let command = ConvertCommand(
            rootDirectory: "/path/to/root",
            bundleIdPrefix: "com.example",
            productType: "staticFramework",
            tuistDir: nil,
            dryRun: false,
            verbose: false
        )

        #expect(command.force == false)
    }
}
