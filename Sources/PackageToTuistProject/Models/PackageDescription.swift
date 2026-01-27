import Foundation

/// Codable types for `swift package describe --type json` output

struct PackageDescription: Codable {
    let name: String
    let manifestDisplayName: String?
    let path: String
    let platforms: [Platform]?
    let products: [Product]
    let targets: [Target]
    let dependencies: [Dependency]?
    let toolsVersion: String?

    init(
        name: String,
        manifestDisplayName: String?,
        path: String,
        platforms: [Platform]?,
        products: [Product],
        targets: [Target],
        dependencies: [Dependency]?,
        toolsVersion: String?
    ) {
        self.name = name
        self.manifestDisplayName = manifestDisplayName
        self.path = path
        self.platforms = platforms
        self.products = products
        self.targets = targets
        self.dependencies = dependencies
        self.toolsVersion = toolsVersion
    }

    /// Returns true if the package has at least one library product
    var hasLibraryProduct: Bool {
        products.contains { $0.type.library != nil }
    }

    enum CodingKeys: String, CodingKey {
        case name
        case manifestDisplayName = "manifest_display_name"
        case path
        case platforms
        case products
        case targets
        case dependencies
        case toolsVersion = "tools_version"
    }

    struct Platform: Codable {
        let name: String
        let version: String

        init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    struct Product: Codable {
        let name: String
        let targets: [String]
        let type: ProductType

        init(name: String, targets: [String], type: ProductType) {
            self.name = name
            self.targets = targets
            self.type = type
        }

        struct ProductType: Codable {
            let library: [String]?
            let executable: Bool?

            init(library: [String]?, executable: Bool?) {
                self.library = library
                self.executable = executable
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.library = try container.decodeIfPresent([String].self, forKey: .library)
                // Handle executable as either a bool or a nested container
                if container.contains(.executable) {
                    self.executable = true
                } else {
                    self.executable = nil
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(library, forKey: .library)
                try container.encodeIfPresent(executable, forKey: .executable)
            }

            enum CodingKeys: String, CodingKey {
                case library
                case executable
            }
        }
    }

    struct Target: Codable {
        let name: String
        let c99name: String?
        let type: String
        let path: String
        let sources: [String]?
        let targetDependencies: [String]?
        let productDependencies: [String]?
        let resources: [Resource]?
        let moduleType: String?

        enum CodingKeys: String, CodingKey {
            case name
            case c99name
            case type
            case path
            case sources
            case targetDependencies = "target_dependencies"
            case productDependencies = "product_dependencies"
            case resources
            case moduleType = "module_type"
        }

        struct Resource: Codable {
            let path: String
            let rule: Rule

            struct Rule: Codable {
                let process: ProcessRule?
                let copy: CopyRule?

                struct ProcessRule: Codable {}
                struct CopyRule: Codable {}
            }
        }
    }

    struct Dependency: Codable {
        let identity: String
        let type: String
        let path: String?
        let url: String?
        let requirement: Requirement?

        struct Requirement: Codable {
            let range: [Range]?
            let exact: [String]?
            let branch: [String]?
            let revision: [String]?

            struct Range: Codable {
                let lowerBound: String
                let upperBound: String

                enum CodingKeys: String, CodingKey {
                    case lowerBound = "lower_bound"
                    case upperBound = "upper_bound"
                }
            }
        }
    }
}
