// swift-tools-version:5.9
//
// Clothesline is built as a Swift package with two targets:
//
//  • ClotheslineCore — pure Foundation logic (item model, persistence, retention,
//    screenshot classification, line geometry). It has no AppKit dependency so it
//    can be unit-tested anywhere, including CI on Linux.
//  • Clothesline     — the macOS app (AppKit + Core Animation + SwiftUI settings).
//
// `Scripts/build-app.sh` wraps the release build into a signed Clothesline.app.
// `project.yml` generates an equivalent Xcode project via XcodeGen if preferred.

import PackageDescription

var targets: [Target] = [
    .target(
        name: "ClotheslineCore",
        path: "Sources/ClotheslineCore"
    ),
    .testTarget(
        name: "ClotheslineCoreTests",
        dependencies: ["ClotheslineCore"],
        path: "Tests/ClotheslineCoreTests"
    ),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Clothesline",
        dependencies: ["ClotheslineCore"],
        path: "Sources/Clothesline",
        linkerSettings: [
            // Embed Info.plist into the executable so `swift run` gets a bundle
            // identifier, LSUIElement and usage strings even outside a .app.
            .unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Resources/Info.plist",
            ]),
            .linkedFramework("Carbon"),
            .linkedFramework("QuickLookUI"),
            .linkedFramework("QuickLookThumbnailing"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
#endif

let package = Package(
    name: "Clothesline",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClotheslineCore", targets: ["ClotheslineCore"]),
    ],
    targets: targets
)
