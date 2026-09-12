// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WL5024ControlFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "WL5024ControlFeature",
            targets: ["WL5024ControlFeature"]
        ),
        .executable(
            name: "WL5024Probe",
            targets: ["WL5024Probe"]
        ),
    ],
    targets: [
        .target(
            name: "WL5024ControlFeature",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "WL5024Probe",
            dependencies: ["WL5024ControlFeature"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "WL5024ProbeTests",
            dependencies: ["WL5024Probe"]
        ),
        .testTarget(
            name: "WL5024ControlFeatureTests",
            dependencies: [
                "WL5024ControlFeature"
            ]
        ),
    ]
)
