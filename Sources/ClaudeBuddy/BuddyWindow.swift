import AppKit
import SwiftUI

/// Borderless, transparent, always-on-top, non-activating panel that never steals focus.
final class BuddyPanel: NSPanel {
    private static let frameKey = "BuddyPanel.origin"

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Resize keeping the bottom-right corner anchored (the character stands on its baseline).
    func resize(to size: CGSize) {
        var f = frame
        let maxX = f.maxX, minY = f.minY
        f.size = NSSize(width: max(size.width, 60), height: max(size.height, 60))
        f.origin = NSPoint(x: maxX - f.width, y: minY)
        setFrame(f, display: true, animate: false)
        saveOrigin()
    }

    func placeInitially() {
        let d = UserDefaults.standard
        if let saved = d.string(forKey: Self.frameKey), let o = NSPointFromString(saved) as NSPoint?, o != .zero,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -50, dy: -50).contains(o) }) {
            setFrameOrigin(o)
        } else {
            resetPosition()
        }
    }

    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.maxX - frame.width - 24, y: v.minY + 12))
        saveOrigin()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        saveOrigin()
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.frameKey)
    }
}
