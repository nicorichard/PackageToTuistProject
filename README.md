# PackageToTuistProject

Convert Swift Package `Package.swift` files into Tuist `Project.swift` files.

## Build

```bash
swift build
```

## Usage

```bash
# Basic usage - scan ./Packages directory
swift run PackageToTuistProject ./Packages

# Preview without writing files
swift run PackageToTuistProject ./Packages --dry-run

# Custom bundle ID prefix
swift run PackageToTuistProject ./Packages --bundle-id-prefix com.mycompany

# Use framework instead of staticFramework
swift run PackageToTuistProject ./Packages --product-type framework

# Verbose output
swift run PackageToTuistProject ./Packages --verbose
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--bundle-id-prefix` | Bundle ID prefix for generated targets | `com.example` |
| `--product-type` | Product type: `staticFramework`, `framework`, `staticLibrary` | `staticFramework` |
| `--tuist-dir` | Path to Tuist directory for dependency validation | `../Tuist` |
| `--dry-run` | Preview changes without writing files | `false` |
| `--verbose` | Enable verbose output | `false` |

## Conversion Mapping

| SPM | Tuist |
|-----|-------|
| `.target()` | `.target(product: .staticFramework)` |
| `.testTarget()` | `.target(product: .unitTests)` |
| `.executableTarget()` | Skipped |
| `.package(path: "../Sibling")` | `.project(target:path:)` |
| `.package(url: "...")` | `.external(name:)` |

## External Dependencies

The tool validates external dependencies against your existing `Tuist/Package.swift` and warns if any are missing:

```
⚠️  External dependency warnings:

Missing dependencies in Tuist/Package.swift:
Add the following to your dependencies array:

    .package(url: "https://github.com/example/lib", from: "1.0.0"),
```
