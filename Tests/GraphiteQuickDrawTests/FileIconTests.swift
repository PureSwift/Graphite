import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteResources
import GraphiteQuickDraw

@Suite struct FileIconTests {

    /// An 'ICN#' member with every pixel black and shown: 32 by 32.
    private let largeIcon = [UInt8](repeating: 0xFF, count: 256)
    /// An 'ics#' member the same: 16 by 16.
    private let smallIcon = [UInt8](repeating: 0xFF, count: 64)

    /// An 'icns' file's bytes.
    private func icns(_ members: [(FourCharCode, [UInt8])]) -> [UInt8] {
        var body: [UInt8] = []
        for (type, bytes) in members {
            body += be(type.rawValue) + be(UInt32(8 + bytes.count)) + bytes
        }
        return be(FourCharCode("icns").rawValue) + be(UInt32(8 + body.count)) + body
    }

    private func be(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    /// A file whose resource fork is in "._name", as macOS copies it.
    private func makeFile(_ folder: TemporaryFolder, _ directory: String, _ name: String, _ resources: [(Resource, [UInt8])]) throws {
        let prefix = directory.isEmpty ? "" : directory + "/"
        folder.write(prefix + name, [])
        var double = AppleDouble()
        double.resourceFork = try ResourceMap.write(resources.map { (resource: $0.0, bytes: $0.1) })
        folder.write(prefix + "._" + name, double.bytes)
    }

    private func customID(_ type: FourCharCode) -> Resource {
        Resource(type: type, id: IconFamily.customIconResourceID)
    }

    @Test func anIcnsFileIsItsOwnIcon() throws {
        let folder = TemporaryFolder()
        folder.write("Large.icns", icns([("ICN#", largeIcon)]))
        folder.write("Upper.ICNS", icns([("ics#", smallIcon)]))
        #expect(IconFamily(ofItemAt: folder.path("Large.icns"))?.sizes == [32])
        #expect(IconFamily(ofItemAt: folder.path("Upper.ICNS"))?.sizes == [16])
    }

    @Test func badIcnsFilesHaveNoIcon() {
        let folder = TemporaryFolder()
        folder.write("Bad.icns", [1, 2, 3, 4, 5, 6, 7, 8, 9])
        folder.write("Empty.icns", [])
        #expect(IconFamily(ofItemAt: folder.path("Bad.icns")) == nil)
        #expect(IconFamily(ofItemAt: folder.path("Empty.icns")) == nil)
        #expect(IconFamily(ofItemAt: folder.path("Missing.icns")) == nil)
        #expect(IconFamily(ofItemAt: folder.path("Missing")) == nil)
    }

    @Test func aFileWithNothingHasNoIcon() {
        let folder = TemporaryFolder()
        folder.write("Plain", [1, 2, 3])
        folder.makeFolder("Folder")
        #expect(IconFamily(ofItemAt: folder.path("Plain")) == nil)
        #expect(IconFamily(ofItemAt: folder.path("Folder")) == nil)
    }

    @Test func customIconInTheResourceFork() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "", "Document", [(customID("ICN#"), largeIcon), (customID("ics#"), smallIcon)])
        let family = try #require(IconFamily(ofItemAt: folder.path("Document")))
        #expect(family.sizes == [16, 32])
        #expect(family.image(size: 32)?.value(column: 0, row: 0) == 0xFF00_0000)
    }

    @Test func customIcnsResource() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "", "Document", [(customID("icns"), icns([("ics#", smallIcon)]))])
        #expect(IconFamily(ofItemAt: folder.path("Document"))?.sizes == [16])
    }

    @Test func iconsOfOtherIDsAreNotCustomIcons() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "", "Application", [(Resource(type: "ICN#", id: 128), largeIcon)])
        #expect(IconFamily(ofItemAt: folder.path("Application")) == nil)
    }

    @Test func aBundlesIconFile() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("App.app")
        folder.makeFolder("App.app/Contents")
        folder.makeFolder("App.app/Contents/Resources")
        folder.write("App.app/Contents/Info.plist", Array("""
            <plist><dict><key>CFBundleIconFile</key><string>AppIcon</string></dict></plist>
            """.utf8))
        folder.write("App.app/Contents/Resources/AppIcon.icns", icns([("ICN#", largeIcon)]))
        #expect(IconFamily(ofItemAt: folder.path("App.app"))?.sizes == [32])
    }

    @Test func aBundlesIconFileWithItsExtension() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("App.app")
        folder.makeFolder("App.app/Contents")
        folder.makeFolder("App.app/Contents/Resources")
        folder.write("App.app/Contents/Info.plist", Array("""
            <plist><dict><key>CFBundleIconFile</key><string>Icon.icns</string></dict></plist>
            """.utf8))
        folder.write("App.app/Contents/Resources/Icon.icns", icns([("ics#", smallIcon)]))
        #expect(IconFamily(ofItemAt: folder.path("App.app"))?.sizes == [16])
    }

    @Test func bundlesWithoutAnIconFileHaveNone() {
        let folder = TemporaryFolder()
        folder.makeFolder("App.app")
        folder.makeFolder("App.app/Contents")
        folder.write("App.app/Contents/Info.plist", Array("<plist><dict><key>CFBundleName</key><string>App</string></dict></plist>".utf8))
        #expect(IconFamily(ofItemAt: folder.path("App.app")) == nil)
        folder.makeFolder("Other.app")
        #expect(IconFamily(ofItemAt: folder.path("Other.app")) == nil)
    }

    @Test func iconFileNamesCannotLeaveTheResourcesFolder() {
        let folder = TemporaryFolder()
        folder.makeFolder("App.app")
        folder.makeFolder("App.app/Contents")
        folder.makeFolder("App.app/Contents/Resources")
        folder.write("Outside.icns", icns([("ICN#", largeIcon)]))
        folder.write("App.app/Contents/Info.plist", Array("""
            <plist><dict><key>CFBundleIconFile</key><string>../../../Outside</string></dict></plist>
            """.utf8))
        #expect(IconFamily(ofItemAt: folder.path("App.app")) == nil)
    }

    @Test func aFoldersCustomIcon() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Pictures")
        try makeFile(folder, "Pictures", "Icon\r", [(customID("ICN#"), largeIcon)])
        #expect(IconFamily(ofItemAt: folder.path("Pictures"))?.sizes == [32])
    }
}
