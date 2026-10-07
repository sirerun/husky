import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import HuskyCore
import HuskyProtocol
import Observation

/// The profile boundary owns transport credentials and persisted outgoing intent.
@MainActor @Observable
final class HuskyLiveChatClient: HuskyChatPanelClient {
  let profiles: HuskyProfileStore
  let conversation = HuskyConversationController()
  private(set) var localStatus: String?
  @ObservationIgnored private var transportTask: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()

  init(profiles: HuskyProfileStore) { self.profiles = profiles }

  var draft: HuskyDraftRecord {
    guard let profile = profiles.selectedProfileID,
      let conversationID = conversation.selectedConversationID
    else { return .init(text: "") }
    return profiles.draft(profileID: profile, conversationID: conversationID)
  }

  func editDraft(_ text: String) {
    guard let profile = profiles.selectedProfileID,
      let conversationID = conversation.selectedConversationID,
      draft.pendingRequestID == nil
    else { return }
    do {
      try profiles.setDraft(.init(text: text), profileID: profile, conversationID: conversationID)
      localStatus = nil
    } catch { localStatus = "The draft could not be saved. Please try again." }
  }

  func selectProfile(_ id: UUID?) async {
    let current = UUID()
    generation = current
    transportTask?.cancel()
    transportTask = nil
    await conversation.detach()
    guard generation == current else { return }
    do {
      try profiles.select(id: id)
      localStatus = nil
      guard let id, let profile = profiles.profiles.first(where: { $0.id == id }) else { return }
      let endpoint = try profile.validatedEndpoint()
      // Token stays local to this transport task, never in observable state.
      let token = try profiles.token(for: id)
      var metadata = Metadata()
      if let token, !token.isEmpty {
        guard !token.contains("\r"), !token.contains("\n") else {
          localStatus = "The saved token is invalid. Replace it in connection settings."
          return
        }
        metadata.addString("Bearer \(token)", forKey: "authorization")
      }
      let requestMetadata = metadata
      let preferred = profiles.lastConversation(profileID: id)
      transportTask = Task { [weak self] in
        do {
          let transport = try HTTP2ClientTransport.Posix.http2NIOPosix(
            target: .dns(host: endpoint.host, port: endpoint.port),
            transportSecurity: endpoint.usesTLS ? .tls : .plaintext)
          try await withGRPCClient(transport: transport) { grpc in
            guard let self, self.generation == current, !Task.isCancelled else { return }
            let api = GRPCHuskyChatClient(
              backend: HuskyHuskyBackend.Client(wrapping: grpc), metadata: requestMetadata)
            await self.conversation.attach(
              profileID: id, client: api, preferredConversationID: preferred)
            while !Task.isCancelled {
              try await Task.sleep(for: .seconds(60))
            }
          }
        } catch {
          guard let self, self.generation == current, !Task.isCancelled else { return }
          await self.conversation.detach()
          guard self.generation == current else { return }
          self.localStatus = "Connection ended. Check the backend settings and reconnect."
        }
      }
    } catch {
      localStatus = "Connection settings could not be loaded. Check the endpoint and saved token."
    }
  }

  func selectConversation(_ id: String) async {
    let current = generation
    let profile = profiles.selectedProfileID
    await conversation.selectConversation(id: id)
    guard generation == current, let profile,
      conversation.selectedConversationID == id
    else { return }
    do { try profiles.setLastConversation(id, profileID: profile) } catch {
      localStatus = "The selected conversation could not be saved."
    }
  }

  func createConversation(title: String) async {
    let current = generation
    let profile = profiles.selectedProfileID
    await conversation.createConversation(title: title)
    guard generation == current, let profile, let id = conversation.selectedConversationID else {
      return
    }
    do { try profiles.setLastConversation(id, profileID: profile) } catch {
      localStatus = "The selected conversation could not be saved."
    }
  }

  func submit(_ text: String) async throws {
    guard let profile = profiles.selectedProfileID,
      let conversationID = conversation.selectedConversationID
    else { throw SendError.unavailable }
    var record = profiles.draft(profileID: profile, conversationID: conversationID)
    if record.pendingRequestID == nil {
      record = .init(text: text, pendingRequestID: UUID().uuidString, pendingText: text)
      try profiles.setDraft(record, profileID: profile, conversationID: conversationID)
    }
    guard let requestID = record.pendingRequestID, let pendingText = record.pendingText,
      pendingText == text
    else { throw SendError.pending }
    let result = await conversation.submitResult(text: pendingText, requestID: requestID)
    if result == .unconfirmed { throw SendError.unknown }
    if result == .rejected {
      let saved = profiles.draft(profileID: profile, conversationID: conversationID)
      if saved.pendingRequestID == requestID {
        try profiles.setDraft(
          .init(text: saved.text), profileID: profile, conversationID: conversationID)
      }
      throw SendError.rejected
    }
    // Use the originating scope even if the UI has switched while awaiting acceptance.
    let saved = profiles.draft(profileID: profile, conversationID: conversationID)
    if saved.pendingRequestID == requestID {
      try profiles.setDraft(.init(text: ""), profileID: profile, conversationID: conversationID)
    }
  }

  func shutdown() async {
    generation = UUID()
    transportTask?.cancel()
    transportTask = nil
    await conversation.detach()
  }

  // Production presentation observes the controller directly; the legacy seam serves demo fixtures.
  func messageUpdates() -> AsyncStream<[HuskyPanelMessage]> { AsyncStream { $0.finish() } }
  func statusUpdates() -> AsyncStream<String?> { AsyncStream { $0.finish() } }

  private enum SendError: LocalizedError {
    case unavailable, pending, unknown, rejected
    var errorDescription: String? {
      switch self {
      case .unavailable: "Select a connected conversation before sending."
      case .pending: "Retry the pending message before editing it."
      case .rejected: "The message was not accepted. Check its length or edit it before retrying."
      case .unknown: "Acceptance is unconfirmed. Retry uses the same message ID."
      }
    }
  }
}
