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
        .target(
            name: "RecmeetCore",
            path: "Sources/RecmeetCore"
        ),
        .executableTarget(
            name: "recmeet",
            dependencies: ["RecmeetCore"],
            path: "Sources/recmeet",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/recmeet/Info.plist",
                ])
            ]
        ),
        .executableTarget(
            name: "RecmeetApp",
            dependencies: ["RecmeetCore"],
            path: "Sources/RecmeetApp",
            exclude: ["Info.plist", "recmeet.entitlements"]
        ),
    ]
)
