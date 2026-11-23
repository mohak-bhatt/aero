// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AeroCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AeroCore", targets: ["AeroCore"])],
    targets: [
        .target(name: "AeroCore", path: "Aero", sources: [
            "Core/PasswordOriginPolicy.swift", "Core/UpdatePolicy.swift", "Browser/SessionStore.swift"
        ]),
        .testTarget(name: "AeroCoreTests", dependencies: ["AeroCore"], path: "Tests/AeroCoreTests")
    ]
)
