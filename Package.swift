// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeConnect",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeConnect", targets: ["ClaudeConnect"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeConnect",
            dependencies: ["SwiftTerm"],
            path: "ClaudeConnect",
            exclude: ["Assets.xcassets"]
        ),
    ]
)
