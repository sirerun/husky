import AppKit
import HuskyWindowing
import SwiftUI

@MainActor
final class HuskyFloatingPanelController {
  private static let frameAutosaveName = NSWindow.FrameAutosaveName("HuskyFloatingChat")
  private let panel: HuskyFloatingPanel
  private let model: HuskyChatPanelModel
  private let diagnosticsEnabled: Bool
  private var screenParametersObserver: NSObjectProtocol?
  private var windowMoveObserver: NSObjectProtocol?

  init(client: any HuskyChatPanelClient, isDemo: Bool = false) {
    model = HuskyChatPanelModel(client: client)
    diagnosticsEnabled = ProcessInfo.processInfo.arguments.contains("--window-diagnostics")

    let nativeScreens = NSScreen.screens
    let areas = Self.screenAreas(from: nativeScreens)
    let activeScreenIndex = Self.activeScreenIndex(in: nativeScreens)
    let fallbackArea = Self.fallbackScreenArea
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
        savedFrame: HuskyPanelGeometry.resizeLegacyDefaultFrame(panel.frame),
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
    observeScreenChanges()
    observeWindowMovement()
    logFrameEvent("initialized")
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

  func resetPosition() {
    let screens = NSScreen.screens
    let areas = Self.screenAreas(from: screens)
    let fallbackArea = Self.fallbackScreenArea
    let usableAreas = areas.isEmpty ? [fallbackArea] : areas
    let activeScreenIndex = Self.activeScreenIndex(in: screens) ?? (areas.isEmpty ? 0 : nil)
    let activeArea =
      activeScreenIndex.flatMap { usableAreas.indices.contains($0) ? usableAreas[$0] : nil }
      ?? usableAreas[0]
    let frame = HuskyPanelGeometry.initialFrame(in: activeArea.visibleFrame)
    panel.setFrame(frame, display: true, animate: false)
    panel.saveFrame(usingName: Self.frameAutosaveName)
    logFrameEvent("reset")
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

  private static func screenAreas(from screens: [NSScreen]) -> [HuskyPanelScreenArea] {
    screens.map { HuskyPanelScreenArea(frame: $0.frame, visibleFrame: $0.visibleFrame) }
  }

  private static var fallbackScreenArea: HuskyPanelScreenArea {
    HuskyPanelScreenArea(
      frame: NSRect(x: 0, y: 0, width: 1024, height: 768),
      visibleFrame: NSRect(x: 0, y: 0, width: 1024, height: 768)
    )
  }

  private func observeScreenChanges() {
    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.reclampCurrentFrame()
      }
    }
  }

  private func observeWindowMovement() {
    guard diagnosticsEnabled else { return }
    windowMoveObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification,
      object: panel,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.logFrameEvent("moved")
      }
    }
  }

  private func reclampCurrentFrame() {
    let nativeScreens = NSScreen.screens
    let areas = Self.screenAreas(from: nativeScreens)
    let usableAreas = areas.isEmpty ? [Self.fallbackScreenArea] : areas
    let activeScreenIndex = Self.activeScreenIndex(in: nativeScreens) ?? (areas.isEmpty ? 0 : nil)
    guard
      let restoration = HuskyPanelGeometry.restore(
        savedFrame: panel.frame,
        screens: usableAreas,
        activeScreenIndex: activeScreenIndex
      )
    else {
      logFrameEvent("screen-change-no-restoration")
      return
    }
    if restoration.frame != panel.frame {
      panel.setFrame(restoration.frame, display: true, animate: false)
      panel.saveFrame(usingName: Self.frameAutosaveName)
      logFrameEvent("screen-change-reclamped")
    } else {
      logFrameEvent("screen-change-unchanged")
    }
  }

  private func logFrameEvent(_ event: String) {
    guard diagnosticsEnabled else { return }
    let screen = panel.screen
    NSLog(
      "[HuskyWindow] event=%@ frame=%@ screenFrame=%@ visibleFrame=%@",
      event,
      NSStringFromRect(panel.frame),
      screen.map { NSStringFromRect($0.frame) } ?? "none",
      screen.map { NSStringFromRect($0.visibleFrame) } ?? "none"
    )
  }
}

private final class HuskyFloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
