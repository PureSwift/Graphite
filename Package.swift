// swift-tools-version:6.4
import PackageDescription

/// Graphite: the Mac Toolbox of the Carbon era, in pure Swift.
///
/// - `GraphiteBase`: the values everything else uses: points and
///   rectangles, four-character codes, errors, Pascal strings and MacRoman,
///   Mac dates, fixed-point and extended numbers, big-endian reading and
///   writing, the Script Manager's answers and Gestalt's table.
/// - `GraphiteTasks`: the Time Manager, Multiprocessing Services and
///   atomic operations on a program's memory.
/// - `GraphiteFiles`: the File Manager over a POSIX file system: FSSpecs,
///   folder IDs, forks, resource forks and Finder info in AppleDouble
///   files, catalog information, aliases and special folders.
/// - `GraphiteResources`: resource maps, resource files written back, the
///   chain of open files, and the typed resources read so far.
/// - `Graphite`: re-exports the modules above.
///
/// Everything here depends only on the Swift standard library, the C
/// library (Glibc, Musl or Darwin) and System (Apple's, or swift-system). No
/// Foundation.
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
        ),
        .library(
            name: "GraphiteTasks",
            targets: ["GraphiteTasks"]
        ),
        .library(
            name: "GraphiteFiles",
            targets: ["GraphiteFiles"]
        ),
        .library(
            name: "GraphiteResources",
            targets: ["GraphiteResources"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-system.git", from: "1.9.0")
    ],
    targets: [
        .target(
            name: "GraphiteBase"
        ),
        .target(
            name: "GraphiteTasks",
            dependencies: ["GraphiteBase"]
        ),
        .target(
            name: "GraphiteFiles",
            dependencies: [
                "GraphiteBase",
                // Apple's System on macOS, or one installed with CMake: else
                // swift-system's package.
                .product(
                    name: "SystemPackage",
                    package: "swift-system",
                    condition: .when(platforms: [.linux, .android, .windows, .wasi, .openbsd])
                )
            ]
        ),
        .target(
            name: "GraphiteResources",
            dependencies: ["GraphiteBase", "GraphiteFiles"]
        ),
        .target(
            name: "Graphite",
            dependencies: ["GraphiteBase", "GraphiteTasks", "GraphiteFiles", "GraphiteResources"]
        ),
        .testTarget(
            name: "GraphiteBaseTests",
            dependencies: ["GraphiteBase"]
        ),
        .testTarget(
            name: "GraphiteTasksTests",
            dependencies: ["GraphiteTasks"]
        ),
        .testTarget(
            name: "GraphiteFilesTests",
            dependencies: ["GraphiteFiles"]
        ),
        .testTarget(
            name: "GraphiteResourcesTests",
            dependencies: ["GraphiteResources"]
        )
    ]
)
