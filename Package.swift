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
/// - `GraphiteAppleEvents`: descriptors, lists, records and Apple events,
///   coercions, and the application's handlers.
/// - `GraphiteQuickDraw`: QuickDraw's pixels, colors, regions, patterns and
///   transfer modes, ports, devices and offscreen worlds.
/// - `GraphiteText`: fonts, the Font Manager's families, the built-in
///   system font, and QuickDraw's text.
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
        ),
        .library(
            name: "GraphiteAppleEvents",
            targets: ["GraphiteAppleEvents"]
        ),
        .library(
            name: "GraphiteQuickDraw",
            targets: ["GraphiteQuickDraw"]
        ),
        .library(
            name: "GraphiteText",
            targets: ["GraphiteText"]
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
            name: "GraphiteAppleEvents",
            dependencies: ["GraphiteBase", "GraphiteFiles"]
        ),
        .target(
            name: "GraphiteQuickDraw",
            dependencies: ["GraphiteBase"]
        ),
        .target(
            name: "GraphiteText",
            dependencies: ["GraphiteBase", "GraphiteQuickDraw"]
        ),
        .target(
            name: "Graphite",
            dependencies: ["GraphiteBase", "GraphiteTasks", "GraphiteFiles", "GraphiteResources", "GraphiteAppleEvents", "GraphiteQuickDraw", "GraphiteText"]
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
        ),
        .testTarget(
            name: "GraphiteAppleEventsTests",
            dependencies: ["GraphiteAppleEvents"]
        ),
        .testTarget(
            name: "GraphiteQuickDrawTests",
            dependencies: ["GraphiteQuickDraw"]
        ),
        .testTarget(
            name: "GraphiteTextTests",
            dependencies: ["GraphiteText"]
        )
    ]
)
