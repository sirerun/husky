import AppKit
import SwiftUI

@MainActor
final class HuskyFloatingPanelController {
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("HuskyFloatingChat")
    private let panel: HuskyFloatingPanel
    private let model: HuskyChatPanelModel

    init(client: any HuskyChatPanelClient, isDemo: Bool = false) {
        model = HuskyChatPanelModel(client: client)

        let screen = Self.activeScreen
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let inset: CGFloat = 24
        let width = min(560, max(320, visibleFrame.width - inset * 2))
        let height = min(680, max(360, visibleFrame.height - inset * 2))
        let initialFrame = NSRect(
            x: visibleFrame.minX + inset,
            y: visibleFrame.minY + inset,
            width: width,
            height: height
        )

        panel = HuskyFloatingPanel(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HuskyChatPanelView(model: model, isDemo: isDemo))

        if panel.setFrameUsingName(Self.frameAutosaveName, force: false) {
            Self.keepReachable(panel, in: screen?.visibleFrame)
        } else {
            panel.setFrame(initialFrame, display: false)
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private static var activeScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
    }

    private static func keepReachable(_ panel: NSWindow, in visibleFrame: NSRect?) {
        guard let visibleFrame else { return }
        var frame = panel.frame
        let inset: CGFloat = 24
        frame.size.width = min(frame.width, max(1, visibleFrame.width - inset * 2))
        frame.size.height = min(frame.height, max(1, visibleFrame.height - inset * 2))
        frame.origin.x = min(
            max(frame.origin.x, visibleFrame.minX + inset),
            visibleFrame.maxX - inset - frame.width
        )
        frame.origin.y = min(
            max(frame.origin.y, visibleFrame.minY + inset),
            visibleFrame.maxY - inset - frame.height
        )
        panel.setFrame(frame, display: false)
    }
}

private final class HuskyFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
