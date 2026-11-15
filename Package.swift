// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iStatus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "iStatus", targets: ["iStatus"])
    ],
    targets: [
        .executableTarget(
            name: "iStatus",
            path: "Sources/iStatus"
        )
    ],
    swiftLanguageModes: [.v5]
)
