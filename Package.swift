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
/// - `GraphiteSound`: sampled sounds from 'snd ' resources and AIFF files,
///   the codecs that decode them, and the channels and mixer that play them.
/// - `GraphiteWindows`: the Window Manager: windows of every class, the
///   window list, FindWindow, zooming and collapsing, the visible and
///   update regions, and the content's buffer the host flushes.
/// - `GraphiteMenus`: the Menu Manager: menus and their items, the menu
///   bar, and the 'MENU' resources that define them.
/// - `GraphiteControls`: the Control Manager: controls of the five kinds,
///   their values, parts and states, the window's list of them, and the
///   'CNTL' resources that define them.
/// - `Graphite`: re-exports the modules above.
///
/// Everything here depends only on the Swift standard library, the C
/// library (Glibc, Musl or Darwin), System (Apple's, or swift-system) and
/// Foundation, which it uses for bytes (`Data`, `ContiguousBytes`) and
/// property lists. `GraphiteText` also depends on swift-freetype, with the
/// `FreeType` trait.
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
        ),
        .library(
            name: "GraphiteSound",
            targets: ["GraphiteSound"]
        ),
        .library(
            name: "GraphiteWindows",
            targets: ["GraphiteWindows"]
        ),
        .library(
            name: "GraphiteMenus",
            targets: ["GraphiteMenus"]
        ),
        .library(
            name: "GraphiteControls",
            targets: ["GraphiteControls"]
        ),
        .library(
            name: "GraphiteDialogs",
            targets: ["GraphiteDialogs"]
        )
    ],
    // FreeType reads outline fonts; builds without it keep the bitmap font.
    traits: [
        .trait(name: "FreeType", description: "Outline fonts through FreeType"),
        .default(enabledTraits: ["FreeType"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-system.git", from: "1.9.0"),
        .package(url: "https://github.com/PureSwift/swift-freetype.git", from: "0.1.1"),
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
            dependencies: ["GraphiteBase", "GraphiteFiles", "GraphiteResources"]
        ),
        .target(
            name: "GraphiteText",
            dependencies: [
                "GraphiteBase", "GraphiteQuickDraw",
                .product(name: "FreeTypeSwift", package: "swift-freetype", condition: .when(traits: ["FreeType"])),
            ]
        ),
        .target(
            name: "GraphiteSound",
            dependencies: ["GraphiteBase"]
        ),
        .target(
            name: "GraphiteWindows",
            dependencies: ["GraphiteBase", "GraphiteQuickDraw"]
        ),
        .target(
            name: "GraphiteMenus",
            dependencies: ["GraphiteBase"]
        ),
        .target(
            name: "GraphiteControls",
            dependencies: ["GraphiteBase"]
        ),
        .target(
            name: "GraphiteDialogs",
            dependencies: ["GraphiteBase", "GraphiteWindows", "GraphiteControls", "GraphiteResources"]
        ),
        .target(
            name: "Graphite",
            dependencies: ["GraphiteBase", "GraphiteTasks", "GraphiteFiles", "GraphiteResources", "GraphiteAppleEvents", "GraphiteQuickDraw", "GraphiteText", "GraphiteSound", "GraphiteWindows", "GraphiteMenus", "GraphiteControls", "GraphiteDialogs"]
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
            dependencies: ["GraphiteQuickDraw", "GraphiteFiles", "GraphiteResources"]
        ),
        .testTarget(
            name: "GraphiteTextTests",
            dependencies: ["GraphiteText"]
        ),
        .testTarget(
            name: "GraphiteSoundTests",
            dependencies: ["GraphiteSound"]
        ),
        .testTarget(
            name: "GraphiteWindowsTests",
            dependencies: ["GraphiteWindows", "GraphiteQuickDraw"]
        ),
        .testTarget(
            name: "GraphiteMenusTests",
            dependencies: ["GraphiteMenus"]
        ),
        .testTarget(
            name: "GraphiteControlsTests",
            dependencies: ["GraphiteControls"]
        ),
        .testTarget(
            name: "GraphiteDialogsTests",
            dependencies: ["GraphiteDialogs"]
        )
    ]
)
