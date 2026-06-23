// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "simple-git",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "simple-git", targets: ["SimpleGit"])
    ],
    targets: [
        .executableTarget(
            name: "SimpleGit",
            path: "Sources/SimpleGit",
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/codex.png"),
                .copy("Resources/claude.png"),
                .copy("Resources/vscode.png")
            ]
        )
    ]
)
