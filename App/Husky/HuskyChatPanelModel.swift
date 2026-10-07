import Foundation
import HuskyCore
import Observation

@Observable
@MainActor
final class HuskyChatPanelModel {
  private var fixtureMessages: [HuskyPanelMessage] = []
  var liveClient: HuskyLiveChatClient? { client as? HuskyLiveChatClient }
  var messages: [HuskyPanelMessage] {
    if let liveClient {
      return liveClient.conversation.messages.map {
        HuskyPanelMessage(id: $0.id, role: $0.role == .user ? .user : .backend, text: $0.text)
      }
    }
    return fixtureMessages
  }
  private(set) var isSending = false
  private var operationStatus: String?
  var statusText: String? {
    operationStatus ?? liveClient?.localStatus ?? liveClient?.conversation.statusText
  }

  private let client: any HuskyChatPanelClient
  @ObservationIgnored private var updatesTask: Task<Void, Never>?
  @ObservationIgnored private var statusTask: Task<Void, Never>?

  init(client: any HuskyChatPanelClient) {
    self.client = client
    updatesTask = Task { [weak self, client] in
      for await messages in client.messageUpdates() {
        guard let self else { return }
        self.fixtureMessages = messages
      }
    }
    statusTask = Task { [weak self, client] in
      for await status in client.statusUpdates() {
        guard let self else { return }
        self.operationStatus = status
      }
    }
  }

  deinit {
    MainActor.assumeIsolated {
      updatesTask?.cancel()
      statusTask?.cancel()
    }
  }

  func submit(_ text: String) async -> Bool {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty, !isSending else { return false }

    isSending = true
    operationStatus = nil
    defer { isSending = false }

    do {
      try await client.submit(trimmedText)
      return true
    } catch {
      operationStatus =
        (error as? LocalizedError)?.errorDescription
        ?? "Message could not be sent. Check the selected connection and try again."
      return false
    }
  }
}
