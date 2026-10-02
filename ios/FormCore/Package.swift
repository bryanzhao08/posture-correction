// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "FormCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "FormCore", targets: ["FormCore"])],
    targets: [
        .target(name: "FormCore"),
        .executableTarget(name: "formcore-check", dependencies: ["FormCore"]),
    ]
)
