// Reading a 'DLOG' resource, as GetNewDialog read one: the dialog's
// rectangle, its window definition ID, whether it is visible, whether it
// has a close box, its reference constant, its item list's resource ID, its
// title with an alignment byte after it, and where it is positioned.

import GraphiteBase
import GraphiteResources
import GraphiteControls
import struct Foundation.Data
import protocol Foundation.ContiguousBytes

public extension Dialog {

    /// Load a DLOG and its DITL through the current resource chain.
    static func make(id: Int16, resources: ResourceChain) throws(MacError) -> Dialog {
        let entry = try resources.get(type: "DLOG", id: id)
        guard let bytes = entry.bytes else { throw .resourceNotFound }
        let dialog = try make(bytes: bytes)
        let list = try resources.get(type: "DITL", id: dialog.itemListID)
        guard let listBytes = list.bytes else { throw .resourceNotFound }
        dialog.itemList = try DialogItemList(bytes: listBytes)
        for item in dialog.itemList.items where item.kind == .control {
            let entry = try resources.get(type: "CNTL", id: item.resourceID)
            guard let bytes = entry.bytes else { throw .resourceNotFound }
            _ = try Control.make(bytes: bytes)
            dialog.controlResources[item.resourceID] = bytes
        }
        return dialog
    }

    /// A 'DLOG' resource without its items, which the 'DITL' of its ID
    /// holds. paramErr for bytes a dialog can't be read from, or a window
    /// definition ID that names none of the Dialog Manager's kinds.
    static func make(bytes: some ContiguousBytes, items: [DialogItem] = []) throws(MacError) -> Dialog {
        var reader = BigEndianReader(bytes)
        do {
            let bounds = try reader.readRect()
            let definitionID = try reader.read(Int16.self)
            let visible = try reader.readBool()
            _ = try reader.read(UInt8.self) // Reserved.
            let hasCloseBox = try reader.readBool()
            _ = try reader.read(UInt8.self) // Reserved.
            let reference = try reader.read(Int32.self)
            let itemListID = try reader.read(Int16.self)
            let title = try reader.readPascalString()
            // An alignment byte when the title's length leaves the next
            // field off a word boundary: its length byte and its bytes.
            if (title.count + 1) % 2 != 0 && reader.remaining > 0 { _ = try reader.read(UInt8.self) }
            let position = reader.remaining == 0 ? 0 : try reader.read(UInt16.self)
            guard let kind = DialogKind(definitionID: definitionID) else { throw MacError.parameter }
            let dialog = Dialog(kind: kind, bounds: bounds, title: title, items: items,
                                reference: reference, hasCloseBox: hasCloseBox, position: position)
            dialog.isVisible = visible
            dialog.itemListID = itemListID
            return dialog
        } catch let error as MacError {
            throw error
        } catch {
            throw MacError.parameter
        }
    }
}
