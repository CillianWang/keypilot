// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keylian",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KeyPilotCore", targets: ["KeyPilotCore"]),
               .executable(name: "Keylian", targets: ["KeyPilot"])],
    targets: [.target(name: "KeyPilotCore"),
              .executableTarget(name: "KeyPilot", dependencies: ["KeyPilotCore"],
                                linkerSettings: [.linkedFramework("Carbon")]),
              .testTarget(name: "KeyPilotCoreTests", dependencies: ["KeyPilotCore"]),
              .testTarget(name: "KeyPilotRuntimeTests", dependencies: ["KeyPilot"])])
