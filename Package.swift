// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyPilot",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KeyPilotCore", targets: ["KeyPilotCore"]),
               .executable(name: "KeyPilot", targets: ["KeyPilot"])],
    targets: [.target(name: "KeyPilotCore"),
              .executableTarget(name: "KeyPilot", dependencies: ["KeyPilotCore"],
                                linkerSettings: [.linkedFramework("Carbon")]),
              .testTarget(name: "KeyPilotCoreTests", dependencies: ["KeyPilotCore"]),
              .testTarget(name: "KeyPilotRuntimeTests", dependencies: ["KeyPilot"])])
