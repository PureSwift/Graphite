// An alert's stages: an 'ALRT' resource keeps, for the first time the user
// triggers the alert and the second, third and fourth-and-later times, four
// bits that say which item the Return key chooses, whether the alert is
// drawn at all, and how many times its sound plays. GetAlertStage counts
// the times, and ResetAlertStage starts over.

import GraphiteBase
import GraphiteResources
import struct Foundation.Data
import protocol Foundation.ContiguousBytes

/// One stage of an alert, the four bits an 'ALRT' resource keeps for it.
public struct AlertStage: Hashable, Sendable {

    /// Which item Return or Enter chooses: the first (bit clear) or the
    /// second (bit set) of the item list.
    public var secondItemIsDefault: Bool

    /// Whether the alert is drawn at this stage.
    public var isDrawn: Bool

    /// How many times the sound plays: 0, 1, 2 or 3, as the two sound bits
    /// count.
    public var soundCount: Int

    public init(secondItemIsDefault: Bool = false, isDrawn: Bool = true, soundCount: Int = 1) {
        self.secondItemIsDefault = secondItemIsDefault
        self.isDrawn = isDrawn
        self.soundCount = soundCount
    }

    /// The high bit selects the default item, followed by the draw bit and
    /// the two-bit sound number.
    public init(bits: UInt8) {
        secondItemIsDefault = bits & 0b1000 != 0
        isDrawn = bits & 0b0100 != 0
        soundCount = Int(bits & 0b11)
    }

    public var bits: UInt8 {
        (secondItemIsDefault ? 8 : 0) | (isDrawn ? 4 : 0) | UInt8(soundCount & 3)
    }

    /// The item Return chooses at this stage: 2 for the second, 1 for the
    /// first.
    public var defaultItem: Int {
        secondItemIsDefault ? 2 : 1
    }
}

/// An 'ALRT' resource: the alert's rectangle, its item list's resource ID,
/// its four stages, and where it is positioned.
public struct AlertResource: Hashable, Sendable {

    public var bounds: Rect

    /// The resource ID of the alert's 'DITL'.
    public var itemListID: Int16

    /// The stages, the first through the fourth-and-later.
    public private(set) var stages: [AlertStage]

    /// The positioning constant: 0 none, or one of the window position
    /// codes the Dialog Manager shared with the Window Manager.
    public var position: UInt16

    public init(bounds: Rect, itemListID: Int16, stages: [AlertStage], position: UInt16 = 0) {
        precondition(stages.count == 4)
        self.bounds = bounds
        self.itemListID = itemListID
        self.stages = stages
        self.position = position
    }

    /// An 'ALRT' resource. paramErr for bytes one can't be read from.
    public init(bytes: some ContiguousBytes) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            bounds = try reader.readRect()
            itemListID = try reader.read(Int16.self)
            let packed = try reader.read(UInt16.self)
            stages = (0..<4).map { AlertStage(bits: UInt8(truncatingIfNeeded: packed >> ($0 * 4))) }
            position = reader.remaining == 0 ? 0 : try reader.read(UInt16.self)
        } catch {
            throw MacError.parameter
        }
    }

    /// The bytes of the 'ALRT' resource.
    public var bytes: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(bounds)
        writer.write(itemListID)
        precondition(stages.count == 4)
        let packed = stages.enumerated().reduce(UInt16(0)) { $0 | (UInt16($1.element.bits) << ($1.offset * 4)) }
        writer.write(packed)
        writer.write(position)
        return writer.bytes
    }

    /// The stage an alert is at: the first three times, then the fourth's.
    public func stage(_ number: Int) -> AlertStage {
        stages[min(max(number, 1), 4) - 1]
    }
}

/// A standard alert's icon and meaning, for the host to present.
public enum AlertKind: Sendable {
    case stop, note, caution, plain
}

/// A host-independent standard alert. Button item numbers match Carbon's
/// OK, Cancel, and Other numbers (1, 2, and 3).
public struct StandardAlert: Sendable {
    public var kind: AlertKind
    public var message: PascalString
    public var explanation: PascalString
    public var defaultText: PascalString
    public var cancelText: PascalString?
    public var otherText: PascalString?
    public var defaultItem: Int
    public var cancelItem: Int

    public init(kind: AlertKind, message: PascalString, explanation: PascalString = "",
                defaultText: PascalString = "OK", cancelText: PascalString? = nil,
                otherText: PascalString? = nil, defaultItem: Int = 1, cancelItem: Int = 0) {
        self.kind = kind
        self.message = message
        self.explanation = explanation
        self.defaultText = defaultText
        self.cancelText = cancelText
        self.otherText = otherText
        self.defaultItem = defaultItem
        self.cancelItem = cancelItem
    }

    /// Present a standard alert and return the chosen button item.
    public func run(bounds: Rect, host: any DialogHost, filter: DialogFilter? = nil) -> Int {
        let dialog = dialog(bounds: bounds)
        host.configureStandardAlert(self, dialog: dialog)
        return dialog.runModal(host: host, filter: filter)
    }

    /// Construct the model for a host to lay out and present.
    public func dialog(bounds: Rect) -> Dialog {
        let width = max(0, Int(bounds.width)), height = max(0, Int(bounds.height))
        func rect(_ top: Int, _ left: Int, _ bottom: Int, _ right: Int) -> Rect {
            Rect(top: Int16(clamping: top), left: Int16(clamping: left),
                 bottom: Int16(clamping: bottom), right: Int16(clamping: right))
        }
        let buttonTop = max(0, height - 32)
        let buttonWidth = max(0, min(80, (width - 32) / 3))
        func button(_ index: Int) -> Rect {
            let right = max(0, width - 12 - index * (buttonWidth + 8))
            return rect(buttonTop, max(0, right - buttonWidth), max(buttonTop, height - 12), right)
        }
        var items = [DialogItem(bounds: button(0), kind: .button, text: defaultText)]
        // Keep the item numbers stable when a button is absent.
        items.append(DialogItem(bounds: cancelText == nil ? .zero : button(1), kind: .button, text: cancelText ?? "", isEnabled: cancelText != nil))
        items.append(DialogItem(bounds: otherText == nil ? .zero : button(2), kind: .button, text: otherText ?? "", isEnabled: otherText != nil))
        items.append(DialogItem(bounds: rect(12, 16, 32, max(16, width - 16)), kind: .staticText, text: message, isEnabled: false))
        items.append(DialogItem(bounds: rect(36, 16, max(36, buttonTop - 8), max(16, width - 16)), kind: .staticText, text: explanation, isEnabled: false))
        let dialog = Dialog(kind: .modal, bounds: bounds, items: items)
        dialog.defaultItem = defaultItem
        dialog.cancelItem = cancelItem
        return dialog
    }
}

/// Load an ALRT and its DITL. The caller decides how to play the stage's
/// alert sound and supplies events when the stage displays a dialog.
public extension AlertResource {
    static func load(id: Int16, resources: ResourceChain) throws(MacError) -> (AlertResource, DialogItemList) {
        let alert = try resources.get(type: "ALRT", id: id)
        guard let bytes = alert.bytes else { throw .resourceNotFound }
        let resource = try AlertResource(bytes: bytes)
        let list = try resources.get(type: "DITL", id: resource.itemListID)
        guard let listBytes = list.bytes else { throw .resourceNotFound }
        return (resource, try DialogItemList(bytes: listBytes))
    }

    func dialog(items: DialogItemList, stage: Int) -> Dialog? {
        let settings = self.stage(stage)
        guard settings.isDrawn else { return nil }
        let dialog = Dialog(kind: .modal, bounds: bounds, items: items.items, position: position)
        dialog.defaultItem = settings.defaultItem
        return dialog
    }
}

/// Runs resource alerts using the host's sound and event delivery.
public final class AlertManager {
    public private(set) var counter = AlertStageCounter()
    public private(set) var lastAlertID: Int16?

    public init() {}

    public func reset() {
        counter.reset()
        lastAlertID = nil
    }

    /// Run an alert using the host for sound, presentation, and input.
    public func run(id: Int16, resource: AlertResource, items: DialogItemList,
                    host: any DialogHost, filter: DialogFilter? = nil) -> Int? {
        if lastAlertID != id { counter.reset() }
        lastAlertID = id
        counter.advance()
        let stageNumber = counter.stage + 1
        let stage = resource.stage(stageNumber)
        if stage.soundCount != 0 { host.playAlertSound(stage.soundCount) }
        guard let dialog = resource.dialog(items: items, stage: stageNumber) else { return nil }
        return dialog.runModal(host: host, filter: filter)
    }

    /// Returns nil for an alert stage that does not display a dialog.
    /// The sound callback receives the selected sound number, 1 through 3.
    public func run(id: Int16, resource: AlertResource, items: DialogItemList,
                    sound: (Int) -> Void, next: () -> DialogEvent?,
                    filter: DialogFilter? = nil) -> Int? {
        if lastAlertID != id { counter.reset() }
        lastAlertID = id
        counter.advance()
        let stageNumber = counter.stage + 1
        let stage = resource.stage(stageNumber)
        if stage.soundCount != 0 { sound(stage.soundCount) }
        guard let dialog = resource.dialog(items: items, stage: stageNumber) else { return nil }
        return dialog.runModal(next: next, filter: filter)
    }
}

/// GetAlertStage and ResetAlertStage's counter: how many times in a row the
/// user has triggered an alert, as many alerts as the program shows.
public struct AlertStageCounter: Hashable, Sendable {

    /// The times so far, the next alert's stage.
    public private(set) var count = 0

    public init() {}

    /// GetAlertStage: the last alert's stage, numbered from 0 through 3.
    public var stage: Int {
        max(0, min(count - 1, 3))
    }

    /// The alert was shown once more; the fourth stage repeats thereafter.
    public mutating func advance() {
        count = min(count + 1, 4)
    }

    /// ResetAlertStage: back to the first stage.
    public mutating func reset() {
        count = 0
    }
}
