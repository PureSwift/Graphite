import Foundation
import Testing
import GraphiteBase
import GraphiteResources

@Suite struct InfoPlistTests {

    private func plist(_ body: String) -> [UInt8] {
        Array("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """.utf8)
    }

    @Test func readsTopLevelStrings() throws {
        let info = try InfoPlist(bytes: plist("""
            <key>CFBundleIconFile</key>
            <string>App</string>
            <key>CFBundleName</key>
            <string>My App</string>
            """))
        #expect(info["CFBundleIconFile"] == "App")
        #expect(info["CFBundleName"] == "My App")
        #expect(info["CFBundleVersion"] == nil)
    }

    @Test func skipsOtherValuesAndKeepsTheKeysStraight() throws {
        let info = try InfoPlist(bytes: plist("""
            <key>LSUIElement</key>
            <true/>
            <key>CFBundleVersion</key>
            <integer>3</integer>
            <key>CFBundleIconFile</key>
            <string>Icon.icns</string>
            """))
        #expect(info["CFBundleIconFile"] == "Icon.icns")
        #expect(info["LSUIElement"] == nil)
        #expect(info["CFBundleVersion"] == nil)
    }

    @Test func ignoresNestedValues() throws {
        let info = try InfoPlist(bytes: plist("""
            <key>CFBundleDocumentTypes</key>
            <array>
                <dict>
                    <key>CFBundleIconFile</key>
                    <string>Wrong</string>
                    <key>Names</key>
                    <array><string>x</string></array>
                </dict>
            </array>
            <key>CFBundleIconFile</key>
            <string>Right</string>
            <key>Empty</key>
            <dict/>
            <key>Name</key>
            <string>After</string>
            """))
        #expect(info["CFBundleIconFile"] == "Right")
        #expect(info["Name"] == "After")
        #expect(info["Names"] == nil)
    }

    @Test func decodesEntities() throws {
        let info = try InfoPlist(bytes: plist("""
            <key>A</key><string>Tom &amp; Jerry &lt;3 &#65;&#x42; &quot;q&quot;</string>
            """))
        #expect(info["A"] == "Tom & Jerry <3 AB \"q\"")
    }

    @Test func emptyStringsAndComments() throws {
        let info = try InfoPlist(bytes: plist("""
            <!-- a comment with <string>fake</string> -->
            <key>E</key><string/>
            <key>F</key><string></string>
            """))
        #expect(info["E"] == "")
        #expect(info["F"] == "")
    }

    @Test func nonASCIIText() throws {
        let info = try InfoPlist(bytes: plist("<key>N</key><string>Café</string>"))
        #expect(info["N"] == "Café")
    }

    @Test func readsBinaryLists() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIconFile": "App", "Count": 3, "Nested": ["CFBundleIconFile": "Wrong"]] as [String: Any],
            format: .binary, options: 0)
        #expect(data.starts(with: Array("bplist".utf8)))
        let info = try InfoPlist(bytes: Array(data))
        #expect(info["CFBundleIconFile"] == "App")
        #expect(info["Count"] == nil)
        #expect(info.strings.count == 1)
    }

    @Test func readsFromAnyBytes() throws {
        let bytes = plist("<key>CFBundleIconFile</key><string>App</string>")
        #expect(try InfoPlist(bytes: bytes)["CFBundleIconFile"] == "App")
        #expect(try InfoPlist(bytes: Data(bytes))["CFBundleIconFile"] == "App")
        #expect(try bytes.withUnsafeBytes { try InfoPlist(bytes: $0) }["CFBundleIconFile"] == "App")
        // A slice keeps its parent's indices; the list is what it holds.
        let padded = Data([1, 2, 3] + bytes)
        #expect(try InfoPlist(bytes: padded[3...])["CFBundleIconFile"] == "App")
    }

    @Test func bytesThatAreNotAListAreAParameterError() {
        #expect(throws: MacError.parameter) { try InfoPlist(bytes: []) }
        #expect(throws: MacError.parameter) { try InfoPlist(bytes: Array("not a plist".utf8)) }
        #expect(throws: MacError.parameter) { try InfoPlist(bytes: Array("bplist00".utf8) + [0, 1, 2]) }
    }

    @Test func aListThatIsNotADictionaryReadsAsEmpty() throws {
        #expect(try InfoPlist(bytes: Array("<plist><array><string>x</string></array></plist>".utf8)).strings.isEmpty)
    }

    @Test func truncatedInputDoesNotTrap() {
        let whole = plist("<key>A</key><string>b</string>")
        for length in 0 ... whole.count {
            _ = try? InfoPlist(bytes: Array(whole.prefix(length)))
        }
    }
}
