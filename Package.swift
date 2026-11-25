// swift-tools-version:6.4
import PackageDescription

/// Graphite: the Mac Toolbox of the Carbon era, in pure Swift.
///
/// - `GraphiteBase`: the values everything else uses: points and
///   rectangles, four-character codes, errors, Pascal strings and MacRoman,
///   Mac dates, fixed-point and extended numbers, big-endian reading and
///   writing, the Script Manager's answers and Gestalt's table.
/// - `Graphite`: re-exports the modules above.
///
/// Everything here depends only on the Swift standard library and the C
/// library (Glibc, Musl or Darwin). No Foundation.
let package = Package(
    name: "Graphite",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Graphite",
            targets: ["Graphite"]
        ),
        .library(
            name: "GraphiteBase",
            targets: ["GraphiteBase"]
        )
    ],
    targets: [
        .target(
            name: "GraphiteBase"
        ),
        .target(
            name: "Graphite",
            dependencies: ["GraphiteBase"]
        ),
        .testTarget(
            name: "GraphiteBaseTests",
            dependencies: ["GraphiteBase"]
        )
    ]
)
