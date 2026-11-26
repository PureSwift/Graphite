// Reading a 'CNTL' resource, as GetNewControl read one: the rectangle
// local to the window, the initial setting, the visibility, the fill byte
// (0, and nothing), the maximum and minimum settings, the control
// definition ID, the reference value, and the title. A pop-up menu's
// minimum is its menu's resource ID, and its maximum the width its title
// takes — the classic's own use of the settings, which the control keeps
// as it kept them.

import GraphiteBase
import struct Foundation.Data
import protocol Foundation.ContiguousBytes

public extension Control {

    /// GetNewControl: a control from a 'CNTL' resource's bytes. menuErr?
    /// no — paramErr for a control definition ID the standard kinds don't
    /// answer and the host hasn't brought a definition for; the bytes
    /// past the title are ignored, as the classic's GetNewControl ignored
    /// them.
    static func make(bytes: some ContiguousBytes) throws(MacError) -> Control {
        var reader = BigEndianReader(bytes)
        do {
            let bounds = try reader.readRect()
            let value = try reader.read(Int16.self)
            let visible = try reader.readBool()
            _ = try reader.read(UInt8.self) // The fill byte, always 0.
            let maximum = try reader.read(Int16.self)
            let minimum = try reader.read(Int16.self)
            let definitionID = try reader.read(Int16.self)
            let reference = try reader.read(Int32.self)
            let title = try reader.readPascalString()
            guard let kind = ControlKind(definitionID: definitionID) else { throw MacError.parameter }
            let control = Control(kind: kind, bounds: bounds, title: title)
            // The range first, then the setting in it: the value's own
            // pinning would hold it to the range it finds.
            control.maximum = Int32(maximum)
            control.minimum = Int32(minimum)
            control.value = Int32(value)
            control.reference = reference
            control.isVisible = visible
            return control
        } catch let error as MacError {
            throw error
        } catch {
            throw MacError.parameter
        }
    }
}
