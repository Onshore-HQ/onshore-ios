// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Onshore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "Onshore", targets: ["Onshore"])],
    targets: [
        .target(name: "Onshore"),
        // Runs against a live install. Not a shipped product: see scripts/e2e.mjs.
        .executableTarget(name: "rv-ios-check", dependencies: ["Onshore"]),
    ]
)
