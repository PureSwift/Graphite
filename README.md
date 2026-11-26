# Graphite

[![Swift](https://img.shields.io/badge/swift-6.4-orange.svg?style=flat)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-71787A.svg)](https://tldrlegal.com/license/mit-license)

The Mac Toolbox of the Carbon era, in pure Swift: QuickDraw; the Resource,
File, Window, Menu, Control and Dialog Managers; Carbon Events, Apple
Events, fonts and the Sound Manager, as Swift types with their own API.

Graphite has three kinds of clients:

- [Perry](https://github.com/MillerTechnologyPeru/Perry), whose Carbon
  provider exports Carbon's C ABI and calls Graphite.
- [Bridge32](https://github.com/colemancda/Bridge32), which runs i386 and
  PowerPC Mac programs on Apple Silicon and needs Carbon's parts that have
  no 64-bit host.
- Linux Swift programs, which import Graphite directly: a resource viewer,
  a file manager that shows classic icons, a port of an old game.

Graphite has no C ABI and no C headers, and doesn't use Foundation. Its
names and types are Swift's (`Rect`, `PascalString`, `MacError`), not
Carbon's spellings: Pascal strings in memory, handles, `OSErr` returns and
Darwin's structure layouts are the job of the layer that exports Carbon.
Any UI it shows will be drawn with [Cacao](https://github.com/PureSwift/Cacao).

> **Status:** early development. `GraphiteBase`, `GraphiteTasks`,
> `GraphiteFiles`, `GraphiteResources`, `GraphiteAppleEvents` and
> `GraphiteQuickDraw` are in place, and `GraphiteText` has begun; FreeType
> faces, ATSUI layouts, the Toolbox's windows, menus, controls and dialogs,
> and the Sound Manager come next.

## Modules

| Module | |
|---|---|
| `GraphiteBase` | Points and rectangles, four-character codes, result codes, Pascal strings and MacRoman, Mac dates and clocks, `Fixed`, `Fract`, 80-bit extended and SANE decimal numbers, QuickDraw's `Random`, big-endian reading and writing, the Script Manager's answers and Gestalt's table. |
| `GraphiteTasks` | The Time Manager, Multiprocessing Services (tasks, queues, events, semaphores, critical regions, aligned memory), `AbsoluteTime` and durations, and atomic operations on a program's memory. |
| `GraphiteFiles` | The File Manager over a POSIX file system: FSSpecs and colon paths, folder IDs, names in any case, forks by reference number, resource forks and Finder info in AppleDouble files (`._name`) or `name.rsrc`, catalog information, aliases that follow moved items, and FindFolder's folders. |
| `GraphiteResources` | The Resource Manager: resource maps read with every offset checked and written back, resource files changed in memory and updated, the chain of open files with `Get` and `Get1` searches, and `STR#`, `STR ` and `vers` resources. |
| `GraphiteAppleEvents` | The Apple Event Manager: descriptors, lists, records and Apple events as values; coercions between text, numbers, booleans, codes, lists, records and file types (`furl`, `fss `, `alis`, and the host's), with installed handlers; the application's handlers by class and ID with wildcards; events sent to itself, and the required events. |
| `GraphiteQuickDraw` | QuickDraw's pixels (1 to 8 bits indexed, 16 and 32 bits direct, big-endian on every CPU, in memory of its own or a program's), colors and the system's color tables, regions as real regions with QuickDraw's region records, patterns, transfer modes, ports, devices and offscreen worlds; drawing rectangles, ovals, round rectangles, arcs, polygons, regions and lines with the pen, and CopyBits, CopyMask and ScrollRect between any depths; PICT pictures, version 1 and 2, with PackBits and QuickTime-compressed images through a decoder the host gives. |
| `GraphiteText` | Fonts: faces and their metrics, the Font Manager's family numbers and names with the classic fonts' and their substitutes, a built-in bitmap system font (from Pomme), and QuickDraw's text in a port's font, face, size and mode, with the styles a face hasn't drawn from its plain glyphs; ATSUI-style layouts with styled runs, line breaking, measuring, hit testing and drawing, and the text in PICT pictures; and, with the `FreeType` trait (on by default), faces from TrueType, OpenType and other outline fonts, found by family name in the system's font folders. |
| `Graphite` | Re-exports the modules above. |

Everything depends only on the Swift standard library, the C library
(Glibc, Musl or Darwin) and System: Apple's on macOS, or one installed
with CMake, else [swift-system](https://github.com/apple/swift-system)'s
package. Graphite builds for Linux on x86_64, arm64, i686
and 32-bit PowerPC, and for macOS, where it can be compared with Apple's
CarbonCore.

## Usage

```swift
import Graphite

let rect = Rect(top: 0, left: 0, bottom: 100, right: 200)
let pinned = rect.pin(Point(v: 150, h: -5))           // (v: 99, h: 0)

let name = PascalString("Café")!                       // MacRoman bytes
let type: FourCharCode = "snd "

let date = MacDate.now.parts                           // DateTimeRec

let files = FileSystem()
let (spec, _) = try files.makeSpec(volume: 0, directory: 0, name: ":Data:Level 1")
let resources = ResourceChain(fileSystem: files)
try resources.open(files.path(of: spec)!)
let messages = try StringList(bytes: resources.get(type: "STR#", id: 128).bytes ?? [])

let queue = MPQueue()
let task = try MPTask.create(queue: queue, terminationWords: (1, 2)) { 0 }
let ended = try queue.wait(timeout: .milliseconds(1000))
```

## Building

Outline fonts need [FreeType](https://freetype.org) (`libfreetype-dev` on
Debian, `brew install freetype` on macOS). Without it, build with
`swift build --disable-default-traits`: text then uses the built-in bitmap
font alone.

```bash
swift build
swift test
```

## License

MIT. Code ported from [Pomme](https://github.com/jorio/Pomme) keeps its MIT
notice in each ported file.
