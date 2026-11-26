// The update region and the buffered content: InvalWindowRect,
// InvalWindowRgn, ValidWindowRect and ValidWindowRgn; BeginUpdate and
// EndUpdate, which hold a window's drawing to what needs it; and
// QDFlushPortBuffer, which tells the host what has changed in the buffer.

import GraphiteBase
import GraphiteQuickDraw

public extension Window {

    /// Whether any of the window needs drawing.
    var needsUpdate: Bool {
        !updateRegion.isEmpty
    }

    /// InvalWindowRect: a part of the window needs drawing. Nothing for a
    /// window with kWindowNoUpdatesAttribute, which draws when it likes.
    func invalidate(_ rect: Rect) {
        invalidate(Region(rect: rect))
    }

    /// InvalWindowRgn.
    func invalidate(_ region: Region) {
        guard !attributes.contains(.noUpdates) else { return }
        updateRegion = updateRegion.union(region)
    }

    /// ValidWindowRect: a part the program has drawn, which no longer
    /// needs it.
    func validate(_ rect: Rect) {
        validate(Region(rect: rect))
    }

    /// ValidWindowRgn.
    func validate(_ region: Region) {
        updateRegion = updateRegion.subtracting(region)
    }

    /// BeginUpdate: holds the window's drawing to the part that needs it.
    /// The port's clip region is saved and set to the update region within
    /// the visible region — the two the same part, in the port's local
    /// coordinates — and the update region is emptied: what's drawn once
    /// is drawn. EndUpdate brings the saved regions back.
    func beginUpdate() {
        guard savedVisibleRegion == nil else { return }
        let origin = contentBounds.topLeft
        let update = updateRegion.offsetBy(dh: -origin.h, dv: -origin.v)
        let area = update.intersection(port.visibleRegion)
        savedClipRegion = port.clipRegion
        savedVisibleRegion = port.visibleRegion
        port.visibleRegion = area
        port.clipRegion = area
        updateRegion = Region()
    }

    /// EndUpdate: the clip and visible regions back as BeginUpdate found
    /// them.
    func endUpdate() {
        guard let clip = savedClipRegion, let visible = savedVisibleRegion else { return }
        port.clipRegion = clip
        port.visibleRegion = visible
        savedClipRegion = nil
        savedVisibleRegion = nil
    }

    /// QDFlushPortBuffer: tells the host the part of the window's content
    /// buffer that has changed, in global coordinates — the whole content
    /// when no part is given. The buffer is the host's to read; it stays
    /// as it was.
    func flush(_ region: Region? = nil) {
        manager?.flushObserver?(self, region ?? contentRegion)
    }

    /// LockPortBits: the host keeps the pixels where they are either way;
    /// programs ask before they touch them.
    func lockPortBits() {
        portBitsLocks += 1
    }

    /// UnlockPortBits.
    func unlockPortBits() {
        portBitsLocks = max(0, portBitsLocks - 1)
    }

    /// IsPortBitsLocked.
    var arePortBitsLocked: Bool {
        portBitsLocks > 0
    }
}
