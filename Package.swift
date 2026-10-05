// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Husky",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HuskyProtocol", targets: ["HuskyProtocol"]),
        .library(name: "HuskyCore", targets: ["HuskyCore"]),
        .executable(name: "Husky", targets: ["Husky"]),
        .executable(name: "HuskyFixtureServer", targets: ["HuskyFixtureServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.3"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", exact: "2.10.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.4.1"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
    ],
    targets: [
        .target(
            name: "HuskyProtocol",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Packages/HuskyProtocol/Sources/HuskyProtocol",
            swiftSettings: [.swiftLanguageMode(.v6)],
            plugins: [
                .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf"),
            ]
        ),
        .target(
            name: "HuskyCore",
            dependencies: [
                "HuskyProtocol",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
            ],
            path: "Packages/HuskyCore/Sources/HuskyCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Husky",
            dependencies: ["HuskyCore"],
            path: "App/Husky",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "HuskyFixture",
            dependencies: [
                "HuskyProtocol",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
            ],
            path: "Tools/HuskyFixture/Sources/HuskyFixture",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "HuskyFixtureServer",
            dependencies: [
                "HuskyFixture",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
            ],
            path: "Tools/HuskyFixture/Sources/HuskyFixtureServer",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HuskyCoreTests",
            dependencies: ["HuskyCore", "HuskyProtocol"],
            path: "Packages/HuskyCore/Tests/HuskyCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HuskyFixtureTests",
            dependencies: [
                "HuskyFixture",
                "HuskyProtocol",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
            ],
            path: "Tools/HuskyFixture/Tests/HuskyFixtureTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
