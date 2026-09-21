// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIStatusLight",
    platforms: [.macOS(.v13)],
    targets: [
        // Tiny ObjC shim: calls the private NSStatusBar priority API with the
        // correct ABI (Swift can't pass non-object args through perform()).
        .target(
            name: "PrivateStatusItem",
            path: "Sources/PrivateStatusItem",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "AIStatusLight",
            dependencies: [.target(name: "PrivateStatusItem")],
            path: "Sources/AIStatusLight"
        )
    ]
)
