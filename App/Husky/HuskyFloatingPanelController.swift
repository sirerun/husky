import AppKit
import SwiftUI

@MainActor
final class HuskyFloatingPanelController {
  private static let frameAutosaveName = NSWindow.FrameAutosaveName("HuskyFloatingChat")
  private let panel: HuskyFloatingPanel
  private let model: HuskyChatPanelModel

  init(client: any HuskyChatPanelClient, isDemo: Bool = false) {
    model = HuskyChatPanelModel(client: client)

    let nativeScreens = NSScreen.screens
    let areas = nativeScreens.map {
      HuskyPanelScreenArea(frame: $0.frame, visibleFrame: $0.visibleFrame)
    }
    let activeScreenIndex = Self.activeScreenIndex(in: nativeScreens)
    let fallbackArea = HuskyPanelScreenArea(
      frame: NSRect(x: 0, y: 0, width: 1024, height: 768),
      visibleFrame: NSRect(x: 0, y: 0, width: 1024, height: 768)
    )
    let usableAreas = areas.isEmpty ? [fallbackArea] : areas
    let usableActiveScreenIndex = activeScreenIndex ?? (areas.isEmpty ? 0 : nil)
    let initialScreen =
      usableActiveScreenIndex.flatMap { usableAreas.indices.contains($0) ? usableAreas[$0] : nil }
      ?? usableAreas[0]
    let initialFrame = HuskyPanelGeometry.initialFrame(in: initialScreen.visibleFrame)

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
      if let restoration = HuskyPanelGeometry.restore(
        savedFrame: panel.frame,
        screens: usableAreas,
        activeScreenIndex: usableActiveScreenIndex
      ) {
        panel.setFrame(restoration.frame, display: false)
      } else {
        panel.setFrame(initialFrame, display: false)
      }
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

  private static func activeScreenIndex(in screens: [NSScreen]) -> Int? {
    let pointer = NSEvent.mouseLocation
    return screens.firstIndex(where: { $0.frame.contains(pointer) })
      ?? NSApp.keyWindow?.screen.flatMap { activeScreen in
        screens.firstIndex(where: { $0 === activeScreen })
      }
      ?? NSScreen.main.flatMap { mainScreen in
        screens.firstIndex(where: { $0 === mainScreen })
      }
  }
}

private final class HuskyFloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
