import Observation
import Foundation

@Observable
@MainActor
final class HuskyChatPanelModel {
    private(set) var messages: [HuskyPanelMessage] = []
    private(set) var isSending = false
    private(set) var statusText: String?

    private let client: any HuskyChatPanelClient
    nonisolated private var updatesTask: Task<Void, Never>?

    init(client: any HuskyChatPanelClient) {
        self.client = client
        updatesTask = Task { [weak self, client] in
            for await messages in client.messageUpdates() {
                guard let self else { return }
                self.messages = messages
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func submit(_ text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !isSending else { return false }

        isSending = true
        statusText = nil
        defer { isSending = false }

        do {
            try await client.submit(trimmedText)
            return true
        } catch {
            statusText = (error as? LocalizedError)?.errorDescription
                ?? "Message could not be sent. Check the selected connection and try again."
            return false
        }
    }
}
