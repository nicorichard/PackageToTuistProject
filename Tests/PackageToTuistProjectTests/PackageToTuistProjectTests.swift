import Testing
import Foundation
@testable import PackageToTuistProject

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
            products: ["MyProduct", "AnotherProduct"]
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
            products: ["MyProduct"]
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
            products: ["ProductA", "ProductB"]
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
            products: ["OtherProduct"]
        )

        let result = collector.classifyDependency(
            productName: "OtherProduct",
            currentPackagePath: URL(fileURLWithPath: "/path/to/package"),
            targetDependencies: [],
            descriptions: [:]
        )

        #expect(result == .project(path: "../OtherPackage", target: "OtherProduct"))
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
}

// MARK: - PackageConverter Tests

@Suite("PackageConverter")
struct PackageConverterTests {
    @Test("converts simple package to Tuist project")
    func convertSimplePackage() {
        let converter = PackageConverter(
            bundleIdPrefix: "com.example",
            productType: "staticFramework"
        )

        let packageJSON = """
        {
            "name": "MyPackage",
            "path": "/path/to/MyPackage",
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
        let project = converter.convert(
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
    func skipsExecutableTargets() {
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
        let project = converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets.count == 1)
        #expect(project.targets[0].name == "MyLib")
    }

    @Test("converts test targets to unitTests product type")
    func convertsTestTargets() {
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
                {"name": "MyLibTests", "type": "test", "path": "Tests/MyLibTests"}
            ]
        }
        """

        let package = try! JSONDecoder().decode(
            PackageDescription.self,
            from: packageJSON.data(using: .utf8)!
        )

        let collector = DependencyCollector()
        let project = converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].product == .unitTests)
    }

    @Test("uses iOS destination by default")
    func defaultsToiOS() {
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
        let project = converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].destinations == ".iOS")
    }

    @Test("uses correct destination for macOS platform")
    func macOSDestination() {
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
        let project = converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].destinations == ".macOS")
    }

    @Test("converts target dependencies correctly")
    func convertsTargetDependencies() {
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
        let project = converter.convert(
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
    func convertsExternalDependencies() {
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
        let project = converter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: collector,
            allDescriptions: [:]
        )

        #expect(project.targets[0].dependencies.count == 1)
        #expect(project.targets[0].dependencies[0] == .external(name: "Alamofire"))
    }

    @Test("respects different product types")
    func respectsProductType() {
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

        let frameworkProject = frameworkConverter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        let staticLibProject = staticLibConverter.convert(
            package: package,
            packagePath: URL(fileURLWithPath: "/path/to/Package.swift"),
            collector: DependencyCollector(),
            allDescriptions: [:]
        )

        #expect(frameworkProject.targets[0].product == .framework)
        #expect(staticLibProject.targets[0].product == .staticLibrary)
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
                    buildableFolders: ["Sources/MyTarget"],
                    dependencies: [],
                    destinations: ".iOS"
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
                    buildableFolders: ["Sources/MyTarget"],
                    dependencies: [],
                    destinations: ".macOS"
                )
            ]
        )

        let output = writer.generate(project: project)

        #expect(output.contains("name: \"MyTarget\""))
        #expect(output.contains("destinations: .macOS"))
        #expect(output.contains("product: .framework"))
        #expect(output.contains("bundleId: \"com.example.MyTarget\""))
        #expect(output.contains("buildableFolders: [\"Sources/MyTarget\"]"))
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
                    buildableFolders: ["Sources/MyTarget"],
                    dependencies: [
                        .target(name: "OtherTarget"),
                        .external(name: "Alamofire"),
                        .project(path: "../Other", target: "OtherLib")
                    ],
                    destinations: ".iOS"
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
                    buildableFolders: ["Sources/Target1"],
                    dependencies: [],
                    destinations: ".iOS"
                ),
                TuistTarget(
                    name: "Target2",
                    product: .staticFramework,
                    bundleId: "com.example.Target2",
                    buildableFolders: ["Sources/Target2"],
                    dependencies: [],
                    destinations: ".iOS"
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
                    buildableFolders: ["Sources/MyTarget"],
                    dependencies: [],
                    destinations: ".iOS"
                )
            ]
        )

        let output = writer.generate(project: project)

        // Should NOT contain dependencies key when empty
        #expect(!output.contains("dependencies:"))
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
