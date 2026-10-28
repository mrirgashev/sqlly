// swift-tools-version: 6.2
import PackageDescription

// Build-only tooling: no dependency is linked into the released application.
let package = Package(
    name: "SQLLYDMGLayout",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/DSStore.git", revision: "6dc395837c3dc371f9c3e71794fab719db74c17a")
    ],
    targets: [
        .executableTarget(name: "SQLLYDMGLayout", dependencies: [.product(name: "DSStore", package: "DSStore")])
    ]
)
