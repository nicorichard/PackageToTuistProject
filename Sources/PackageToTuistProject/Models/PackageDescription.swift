import Foundation

/// Decodable types for `swift package describe --type json` output

struct PackageDescription: Decodable {
    let name: String
    let manifestDisplayName: String?
    let path: String
    let platforms: [Platform]?
    let products: [Product]
    let targets: [Target]
    let dependencies: [Dependency]?
    let toolsVersion: String?

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

    struct Platform: Decodable {
        let name: String
        let version: String
    }

    struct Product: Decodable {
        let name: String
        let targets: [String]
        let type: ProductType

        struct ProductType: Decodable {
            let library: [String]?
            let executable: Bool?

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

            enum CodingKeys: String, CodingKey {
                case library
                case executable
            }
        }
    }

    struct Target: Decodable {
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

        struct Resource: Decodable {
            let path: String
            let rule: Rule

            struct Rule: Decodable {
                let process: ProcessRule?
                let copy: CopyRule?

                struct ProcessRule: Decodable {}
                struct CopyRule: Decodable {}
            }
        }
    }

    struct Dependency: Decodable {
        let identity: String
        let type: String
        let path: String?
        let url: String?
        let requirement: Requirement?

        struct Requirement: Decodable {
            let range: [Range]?
            let exact: [String]?
            let branch: [String]?
            let revision: [String]?

            struct Range: Decodable {
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
