# PackageToTuistProject

Convert Swift Package `Package.swift` files into Tuist `Project.swift` files that **just works**.

## Build

```bash
swift build
```

## Usage

```bash
PackageToTuistProject ./Path/To/Package
```

### Examples

```bash
# Preview without writing files
PackageToTuistProject ./Packages --dry-run

# Filter to iOS only
PackageToTuistProject ./Packages --platform ios

# Filter to multiple platforms
PackageToTuistProject ./Packages --platform ios --platform macos

# Custom bundle ID prefix
PackageToTuistProject ./Packages --bundle-id-prefix com.mycompany

# Use framework instead of staticFramework
PackageToTuistProject ./Packages --product-type framework
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--platform` | Filter to specific platforms (can be repeated). Values: `ios`, `macos`, `tvos`, `watchos`, `visionos` | all |
| `--bundle-id-prefix` | Bundle ID prefix for generated targets | `com.example` |
| `--product-type` | Product type: `staticFramework`, `framework`, `staticLibrary` | `staticFramework` |
| `--tuist-dir` | Path to Tuist directory for dependency validation | `../Tuist` |
| `--dry-run` | Preview changes without writing files | `false` |
| `--verbose` | Enable verbose output | `false` |
| `--force` | Regenerate all files, ignoring cached package descriptions | `false` |

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

## Design Goals

This tool makes a best-effort to preserve existing Swift Package functionality, allowing incremental Tuist adoption over an existing Swift Package without requiring manual configuration adjustments.
