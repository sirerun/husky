import AppKit
import SwiftUI

enum HuskyMaterialCandidate: String, CaseIterable, Identifiable, Equatable {
  case hudWindow
  case popover
  case underWindow
  case customTint

  var id: String { rawValue }

  var title: String {
    switch self {
    case .hudWindow: "HUD material"
    case .popover: "Popover material"
    case .underWindow: "Under-window material"
    case .customTint: "Custom tint"
    }
  }

  var appKitMaterial: NSVisualEffectView.Material? {
    switch self {
    case .hudWindow: .hudWindow
    case .popover: .popover
    case .underWindow: .underWindowBackground
    case .customTint: nil
    }
  }
}

struct HuskyMaterialSurface: NSViewRepresentable {
  let candidate: HuskyMaterialCandidate
  let cornerRadius: CGFloat

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = HuskyDraggableMaterialView()
    configure(view)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    configure(view)
  }

  private func configure(_ view: NSVisualEffectView) {
    view.material = candidate.appKitMaterial ?? .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = candidate == .customTint ? .inactive : .active
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.masksToBounds = true
    view.isEmphasized = false
  }
}

/// Only material background receives these events; text and composer controls
/// retain their own hit testing and selection behavior above the background.
private final class HuskyDraggableMaterialView: NSVisualEffectView {
  override var mouseDownCanMoveWindow: Bool { true }

  override func mouseDown(with event: NSEvent) {
    guard let window else {
      super.mouseDown(with: event)
      return
    }
    window.performDrag(with: event)
  }
}
