// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TextAdder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TextAdder", path: "Sources/TextAdder"),
        .testTarget(
            name: "TextAdderTests",
            dependencies: ["TextAdder"],
            path: "Tests/TextAdderTests"
        ),
    ]
)
