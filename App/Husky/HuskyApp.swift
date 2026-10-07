import AppKit
import HuskyCore
import SwiftUI

@main
struct HuskyApp: App {
  @NSApplicationDelegateAdaptor(HuskyAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
private final class HuskyAppDelegate: NSObject, NSApplicationDelegate {
  private var panelController: HuskyFloatingPanelController?
  private var chatClient: (any HuskyChatPanelClient)?
  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    let fixtureMode = ProcessInfo.processInfo.arguments.contains("--fixture-mode")
    let client: any HuskyChatPanelClient
    if fixtureMode {
      client = HuskyGRPCFixtureChatClient(
        port: Self.fixturePort(from: ProcessInfo.processInfo.arguments))
    } else if demo {
      client = HuskyDemoChatClient()
    } else {
      do {
        let live = HuskyLiveChatClient(profiles: try HuskyProfileStore())
        client = live
        Task { await live.selectProfile(live.profiles.selectedProfileID) }
      } catch {
        client = HuskyUnconfiguredChatClient()
      }
    }
    chatClient = client
    panelController = HuskyFloatingPanelController(
      client: client,
      isDemo: demo || fixtureMode
    )
    panelController?.show()
    configureStatusItem()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    panelController?.show()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let chatClient else { return .terminateNow }
    Task {
      await chatClient.shutdown()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Husky")
    item.button?.target = self
    item.button?.action = #selector(togglePanel)

    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(title: "Show or Hide Husky", action: #selector(togglePanel), keyEquivalent: ""))
    menu.addItem(
      NSMenuItem(
        title: "Reset Window Position", action: #selector(resetPosition), keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Husky", action: #selector(quit), keyEquivalent: "q"))
    for menuItem in menu.items {
      menuItem.target = self
    }
    item.menu = menu
    statusItem = item
  }

  @objc private func togglePanel() {
    panelController?.toggle()
  }

  @objc private func resetPosition() {
    panelController?.resetPosition()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private static func fixturePort(from arguments: [String]) -> Int {
    guard let index = arguments.firstIndex(of: "--fixture-port"),
      arguments.indices.contains(index + 1),
      let port = Int(arguments[index + 1]),
      (1...65_535).contains(port)
    else {
      return 50_051
    }
    return port
  }
}

@MainActor
private final class HuskyUnconfiguredChatClient: HuskyRecoverableSettingsClient {
  func recoverSettings() throws {
    try HuskyProfileStore.recoverPreferences()
  }
  private enum ClientError: LocalizedError {
    case noBackend

    var errorDescription: String? {
      "No backend is configured yet. Connect a backend to send messages."
    }
  }

  func messageUpdates() -> AsyncStream<[HuskyPanelMessage]> {
    AsyncStream { continuation in
      continuation.yield([])
      continuation.finish()
    }
  }

  func statusUpdates() -> AsyncStream<String?> {
    AsyncStream { continuation in
      continuation.yield(
        "Saved connection settings could not be opened. Check local storage and Keychain access, then restart Husky."
      )
      continuation.finish()
    }
  }

  func shutdown() async {}

  func submit(_ text: String) async throws {
    throw ClientError.noBackend
  }
}

@MainActor
private final class HuskyDemoChatClient: HuskyChatPanelClient {
  private var messages = [
    HuskyPanelMessage(
      id: "demo-user-1",
      role: .user,
      text: "Can I read earlier messages without the latest one moving?"
    ),
    HuskyPanelMessage(
      id: "demo-backend-1",
      role: .backend,
      text:
        "This is a static local demo fixture. The production backend connection is not configured."
    ),
  ]
  private var continuation: AsyncStream<[HuskyPanelMessage]>.Continuation?

  func messageUpdates() -> AsyncStream<[HuskyPanelMessage]> {
    let (stream, continuation) = AsyncStream<[HuskyPanelMessage]>.makeStream()
    self.continuation = continuation
    continuation.yield(messages)
    return stream
  }

  func statusUpdates() -> AsyncStream<String?> {
    AsyncStream { continuation in
      continuation.yield("Static local demo; no backend connection")
      continuation.finish()
    }
  }

  func shutdown() async {}

  func submit(_ text: String) async throws {
    messages.append(HuskyPanelMessage(id: UUID().uuidString, role: .user, text: text))
    continuation?.yield(messages)
  }
}
