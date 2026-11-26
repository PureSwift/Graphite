// An item list, the 'DITL' resource: the items of a dialog box or an alert
// box, in the order the Dialog Manager numbered them. Read with every
// offset checked: each item is its rectangle, its type byte with the enable
// flag in its high bit, and its text or its resource, padded to a word as
// the resource compiler padded it.

import GraphiteBase
import struct Foundation.Data
import protocol Foundation.ContiguousBytes

public struct DialogItemList: Sendable {

    /// The items, first to last.
    public var items: [DialogItem]

    /// An empty list.
    public init() {
        items = []
    }

    public init(items: [DialogItem]) {
        self.items = items
    }

    /// CountDITL.
    public var count: Int { items.count }

    /// The item of a number the Dialog Manager's routines take, which
    /// count from 1; nil for a number no item has.
    public func item(_ number: Int) -> DialogItem? {
        number >= 1 && number <= items.count ? items[number - 1] : nil
    }

    /// FindDialogItem: the item a point is in, numbered from 0; the first
    /// when items overlap, and nil for a point in none.
    public func findItem(at point: Point) -> Int? {
        items.firstIndex { $0.contains(point) }
    }

    // MARK: The resource

    /// A 'DITL' resource: its count less one, then the items. paramErr for
    /// bytes a list can't be read from — a count past what the bytes hold,
    /// an item cut off, an item of a type whose bytes aren't defined.
    public init(bytes: some ContiguousBytes) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            let count = Int(try reader.read(Int16.self)) + 1
            guard count >= 0 else { throw MacError.parameter }
            var items: [DialogItem] = []
            items.reserveCapacity(count)
            for _ in 0 ..< count {
                _ = try reader.read(UInt32.self) // Reserved: the Dialog Manager's own storage.
                let bounds = try reader.readRect()
                let typeByte = try reader.read(UInt8.self)
                guard let kind = DialogItemKind(rawValue: typeByte & ~DialogItemKind.disableBit) else {
                    throw MacError.parameter
                }
                let isEnabled = typeByte & DialogItemKind.disableBit == 0
                var item = DialogItem(bounds: bounds, kind: kind, isEnabled: isEnabled)
                switch kind {
                case .button, .checkBox, .radioButton, .staticText, .editText:
                    item.text = try reader.readPascalString()
                    if reader.offset % 2 != 0 { try reader.skip(1) }
                case .control, .icon, .picture:
                    _ = try reader.read(UInt8.self) // Reserved.
                    item.resourceID = try reader.read(Int16.self)
                case .helpItem:
                    let size = Int(try reader.read(UInt8.self))
                    _ = try reader.read(UInt16.self) // The help item's type.
                    item.resourceID = try reader.read(Int16.self)
                    // HMScanAppendhdlg's items carry an item number too.
                    if size > 4 { _ = try reader.read(UInt16.self) }
                case .userItem:
                    _ = try reader.read(UInt8.self) // Reserved.
                }
                items.append(item)
            }
            self.items = items
        } catch let error as MacError {
            throw error
        } catch {
            throw MacError.parameter
        }
    }

    /// The list's bytes as a 'DITL' resource keeps them.
    public var bytes: [UInt8] {
        var writer = BigEndianWriter()
        precondition(items.count <= Int(Int16.max) + 1)
        writer.write(Int16(items.count - 1))
        for item in items {
            writer.write(UInt32(0))
            writer.write(item.bounds)
            writer.write(item.typeByte)
            switch item.kind {
            case .button, .checkBox, .radioButton, .staticText, .editText:
                writer.write(item.text)
                writer.align(to: 2)
            case .control, .icon, .picture, .userItem:
                writer.write(UInt8(0))
                if item.kind != .userItem { writer.write(item.resourceID) }
            case .helpItem:
                writer.write(UInt8(4))
                writer.write(UInt16(1))
                writer.write(item.resourceID)
            }
        }
        return writer.bytes
    }
}
