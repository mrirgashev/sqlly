// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SQLLY",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SQLLY", targets: ["SQLLY"]),
        .library(name: "SQLCore", targets: ["SQLCore"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "CPQShim", publicHeadersPath: "include"),
        .target(name: "SQLCore", dependencies: ["CSQLite", "CPQShim"], resources: [.copy("Resources")]),
        .executableTarget(name: "SQLLY", dependencies: ["SQLCore"], resources: [.process("Resources")]),
        .testTarget(name: "SQLCoreTests", dependencies: ["SQLCore"])
    ]
)
