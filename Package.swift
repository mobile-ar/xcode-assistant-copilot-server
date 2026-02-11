// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "xcode-assistant-copilot-sever",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "xcode-assistant-copilot-sever",
            targets: ["xcode-assistant-copilot-sever"]
        ),
        .library(
            name: "XcodeAssistantCopilotServer",
            targets: ["XcodeAssistantCopilotServer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.20.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "XcodeAssistantCopilotServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/XcodeAssistantCopilotServer"
        ),
        .executableTarget(
            name: "xcode-assistant-copilot-sever",
            dependencies: [
                "XcodeAssistantCopilotServer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "XcodeAssistantCopilotServerTests",
            dependencies: ["XcodeAssistantCopilotServer"],
            path: "Tests/XcodeAssistantCopilotServerTests"
        ),
    ]
)
