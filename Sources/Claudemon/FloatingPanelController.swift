import AppKit
import SwiftUI
import ClaudemonCore

/// Manages a borderless, always-on-top, non-activating NSPanel hosting the
/// compact SwiftUI widget. The panel is draggable by its background and does
/// not steal focus from the active app.
@MainActor
final class FloatingPanelController {

    private var panel: NSPanel?
    private let store: UsageStore
    private static let frameAutosaveName = "ClaudemonFloatingPanel"

    init(store: UsageStore) {
        self.store = store
        // Resize the panel whenever the form changes.
        store.floatingFormChange = { [weak self] form in
            self?.setForm(form)
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        // orderFrontRegardless avoids activating the app (no focus steal).
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let form = store.floatingForm
        let contentSize = Self.contentSize(for: form)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: FloatingWidgetView(store: store))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Double-click toggles between the large and mini forms. A click gesture
        // recognizer (2 clicks) coexists with `isMovableByWindowBackground`: a
        // drag fails the click recognizer, so dragging the panel still works.
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        hosting.addGestureRecognizer(doubleClick)

        // Restore prior position, or place near top-right of the main screen.
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        // The autosave may have stored the OTHER form's size; reconcile the
        // restored frame's size with the persisted form, keeping the top-left
        // corner stable.
        reconcileSize(panel, form: form)
        if panel.frame.origin == .zero {
            positionDefault(panel)
        }

        return panel
    }

    @objc private func handleDoubleClick() {
        // Advancing drives both the SwiftUI re-render (@Observable) and, via the
        // store's change callback, this controller's panel resize.
        store.floatingForm = store.floatingForm.next
    }

    /// Resize the panel to fit the given form, keeping the top-left corner stable
    /// and clamping to the current screen so it never jumps off-screen.
    private func setForm(_ form: FloatingForm) {
        guard let panel else { return }
        let frame = Self.clamp(Self.frame(of: panel, form: form),
                               to: panel.screen ?? NSScreen.main)
        panel.setFrame(frame, display: true, animate: true)
    }

    /// Force a restored panel's size to match the persisted form without moving
    /// its top-left corner.
    private func reconcileSize(_ panel: NSPanel, form: FloatingForm) {
        let frame = Self.frame(of: panel, form: form)
        guard frame.size != panel.frame.size else { return }
        panel.setFrame(frame, display: false)
    }

    /// The panel's frame resized to the given form with its top-left corner
    /// held in place (macOS origin is bottom-left, so the top edge is maxY).
    private static func frame(of panel: NSPanel, form: FloatingForm) -> NSRect {
        let size = contentSize(for: form)
        return NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private static func contentSize(for form: FloatingForm) -> NSSize {
        let size = FloatingWidgetView.contentSize(for: form)
        return NSSize(width: size.width, height: size.height)
    }

    /// Nudge a frame fully inside a screen's visible area when possible.
    private static func clamp(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return frame }
        var f = frame
        f.origin.x = min(max(f.origin.x, visible.minX), visible.maxX - f.width)
        f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
        return f
    }

    private func positionDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 24
        let y = visible.maxY - panel.frame.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
