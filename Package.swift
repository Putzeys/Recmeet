// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "recmeet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "recmeet", targets: ["recmeet"]),
        .executable(name: "RecmeetApp", targets: ["RecmeetApp"]),
        .executable(name: "RecmeetWin32App", targets: ["RecmeetWin32App"]),
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

        // C shim that bridges Windows audio headers (mmdeviceapi / audioclient
        // / propsys / propkey) and re-exports macro constants Swift can't import
        // directly. Compiles to a no-op on non-Windows hosts.
        .target(
            name: "CWASAPI",
            path: "Sources/CWASAPI",
            publicHeadersPath: "include"
        ),

        // Windows: WASAPI via WinSDK + CWASAPI shim.
        .target(
            name: "RecmeetCoreWindows",
            dependencies: [
                "RecmeetCore",
                .target(name: "CWASAPI", condition: .when(platforms: [.windows])),
            ],
            path: "Sources/RecmeetCoreWindows",
            linkerSettings: [
                .linkedLibrary("ole32", .when(platforms: [.windows])),
            ]
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

        // Native Windows GUI. Pure Swift via WinSDK — no Windows App SDK
        // runtime, no extra DLLs, distributable as a single .exe under 10 MB.
        // Compiles to a stub on macOS so the package as a whole stays
        // cross-platform, but the app only actually does anything on Windows.
        .executableTarget(
            name: "RecmeetWin32App",
            dependencies: [
                "RecmeetCore",
                .target(name: "RecmeetCoreWindows", condition: .when(platforms: [.windows])),
            ],
            path: "Sources/RecmeetWin32App",
            exclude: ["recmeet.rc", "recmeet.ico"],
            linkerSettings: [
                .linkedLibrary("comctl32", .when(platforms: [.windows])),
                .linkedLibrary("shell32",  .when(platforms: [.windows])),
                .linkedLibrary("user32",   .when(platforms: [.windows])),
                .linkedLibrary("gdi32",    .when(platforms: [.windows])),
                // Build as a real GUI app (no console window). We keep the
                // CRT entry point so our top-level main.swift code still runs.
                .unsafeFlags(
                    ["-Xlinker", "/SUBSYSTEM:WINDOWS",
                     "-Xlinker", "/ENTRY:mainCRTStartup"],
                    .when(platforms: [.windows])
                ),
            ]
        ),
    ]
)
