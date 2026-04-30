// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "recmeet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "recmeet", targets: ["recmeet"]),
        .executable(name: "RecmeetApp", targets: ["RecmeetApp"]),
        .library(name: "RecmeetCore", targets: ["RecmeetCore"]),
    ],
    targets: [
        // Cross-platform: Foundation only.
        .target(
            name: "RecmeetCore",
            path: "Sources/RecmeetCore"
        ),

        // macOS: AVFoundation + ScreenCaptureKit + CoreAudio HAL.
        .target(
            name: "RecmeetCoreApple",
            dependencies: ["RecmeetCore"],
            path: "Sources/RecmeetCoreApple"
        ),

        // Windows: WASAPI via WinSDK.
        .target(
            name: "RecmeetCoreWindows",
            dependencies: ["RecmeetCore"],
            path: "Sources/RecmeetCoreWindows"
        ),

        .executableTarget(
            name: "recmeet",
            dependencies: [
                "RecmeetCore",
                .target(name: "RecmeetCoreApple",   condition: .when(platforms: [.macOS])),
                .target(name: "RecmeetCoreWindows", condition: .when(platforms: [.windows])),
            ],
            path: "Sources/recmeet",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker", "-sectcreate",
                        "-Xlinker", "__TEXT",
                        "-Xlinker", "__info_plist",
                        "-Xlinker", "Sources/recmeet/Info.plist",
                    ],
                    .when(platforms: [.macOS])
                )
            ]
        ),

        .executableTarget(
            name: "RecmeetApp",
            dependencies: ["RecmeetCore", "RecmeetCoreApple"],
            path: "Sources/RecmeetApp",
            exclude: ["Info.plist", "recmeet.entitlements"]
        ),
    ]
)
