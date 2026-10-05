import AppKit
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
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        let client: any HuskyChatPanelClient = demo ? HuskyDemoChatClient() : HuskyUnconfiguredChatClient()
        panelController = HuskyFloatingPanelController(client: client, isDemo: demo)
        panelController?.show()
        configureStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Husky")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show or Hide Husky", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Husky", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() {
        panelController?.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class HuskyUnconfiguredChatClient: HuskyChatPanelClient {
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
            text: "This is a static local demo fixture. The production backend connection is not configured."
        )
    ]
    private var continuation: AsyncStream<[HuskyPanelMessage]>.Continuation?

    func messageUpdates() -> AsyncStream<[HuskyPanelMessage]> {
        let (stream, continuation) = AsyncStream<[HuskyPanelMessage]>.makeStream()
        self.continuation = continuation
        continuation.yield(messages)
        return stream
    }

    func submit(_ text: String) async throws {
        messages.append(HuskyPanelMessage(id: UUID().uuidString, role: .user, text: text))
        continuation?.yield(messages)
    }
}
