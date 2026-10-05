import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import HuskyCore
import HuskyProtocol

@MainActor
final class HuskyGRPCFixtureChatClient: HuskyChatPanelClient {
  private enum FixtureClientError: LocalizedError {
    case notConnected

    var errorDescription: String? {
      switch self {
      case .notConnected:
        return "Start HuskyFixtureServer with --fixture-mode on 127.0.0.1:50051, then retry."
      }
    }
  }

  private let port: Int
  private var messages: [HuskyPanelMessage] = []
  private var statusText: String? = "Connecting to local gRPC fixture…"
  private var messagesContinuation: AsyncStream<[HuskyPanelMessage]>.Continuation?
  private var statusContinuation: AsyncStream<String?>.Continuation?
  private var connectionTask: Task<Void, Never>?
  private var session: (any HuskyConversationSession)?
  private var conversationID: String?

  init(port: Int) {
    self.port = port
  }

  func messageUpdates() -> AsyncStream<[HuskyPanelMessage]> {
    let (stream, continuation) = AsyncStream<[HuskyPanelMessage]>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    self.messagesContinuation = continuation
    continuation.yield(self.messages)
    self.startIfNeeded()
    return stream
  }

  func statusUpdates() -> AsyncStream<String?> {
    let (stream, continuation) = AsyncStream<String?>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    self.statusContinuation = continuation
    continuation.yield(self.statusText)
    self.startIfNeeded()
    return stream
  }

  func submit(_ text: String) async throws {
    guard let session = self.session else { throw FixtureClientError.notConnected }
    try await session.submit(requestID: UUID().uuidString, text: text)
  }

  func shutdown() async {
    if let session = self.session {
      await session.end()
    }
    self.connectionTask?.cancel()
    self.messagesContinuation?.finish()
    self.statusContinuation?.finish()
  }

  private func startIfNeeded() {
    guard self.connectionTask == nil else { return }
    self.connectionTask = Task { [weak self] in
      guard let self else { return }
      await self.runConnection()
    }
  }

  private func runConnection() async {
    while !Task.isCancelled {
      do {
        let transport = try HTTP2ClientTransport.Posix.http2NIOPosix(
          target: .ipv4(address: "127.0.0.1", port: self.port),
          transportSecurity: .plaintext
        )
        try await withGRPCClient(transport: transport) { grpcClient in
          let backend = HuskyHuskyBackend.Client(wrapping: grpcClient)
          let api = GRPCHuskyChatClient(backend: backend)
          let capabilities = try await api.getCapabilities()
          let firstPage = try await api.listConversations(
            pageSize: capabilities.defaultHistoryPageSize,
            before: nil
          )
          let rememberedID = self.conversationID
          var rememberedConversation: HuskyConversation?
          if let rememberedID {
            rememberedConversation = firstPage.conversations.first { $0.id == rememberedID }
            var nextCursor = firstPage.nextCursor
            var hasMore = firstPage.hasMore
            while rememberedConversation == nil, hasMore, let cursor = nextCursor {
              let page = try await api.listConversations(
                pageSize: capabilities.defaultHistoryPageSize,
                before: cursor
              )
              rememberedConversation = page.conversations.first { $0.id == rememberedID }
              nextCursor = page.nextCursor
              hasMore = page.hasMore
            }
          }
          let conversation: HuskyConversation
          if let rememberedConversation {
            conversation = rememberedConversation
          } else if let first = firstPage.conversations.first {
            conversation = first
          } else {
            conversation = try await api.createConversation(
              requestID: UUID().uuidString,
              title: "Local fixture conversation"
            )
          }
          self.conversationID = conversation.id
          let history = try await api.getHistory(
            conversationID: conversation.id,
            pageSize: capabilities.defaultHistoryPageSize,
            before: nil
          )
          self.messages = history.messages.map(Self.panelMessage)
          self.publishMessages()
          let session = try await api.openConversation(
            conversationID: conversation.id,
            afterSequence: history.snapshotSequence,
            resumeToken: nil
          )
          self.session = session
          var cursor = HuskyEventCursor(
            conversationID: conversation.id,
            afterSequence: history.snapshotSequence
          )
          self.publishStatus("Connected to deterministic local gRPC fixture")

          for try await sequencedEvent in session.events {
            switch try cursor.stage(sequencedEvent) {
            case .ignoreDuplicate:
              continue
            case .resynchronize:
              if case .resyncRequired(_, _, let reason) = sequencedEvent.event {
                self.publishStatus("Fixture history expired; recovering: \(reason)")
              } else {
                self.publishStatus("Fixture event gap; reloading canonical history")
              }
              return
            case .deliver:
              self.apply(sequencedEvent.event)
              try cursor.acknowledge(sequencedEvent)
            }
          }
        }
        self.session = nil
        guard !Task.isCancelled else { return }
        self.publishStatus("Fixture stream closed; reconnecting from canonical history…")
      } catch is CancellationError {
        self.session = nil
        self.publishStatus(nil)
        return
      } catch {
        self.session = nil
        guard !Task.isCancelled else { return }
        self.publishStatus(
          "Local fixture unavailable: \(error.localizedDescription). Retrying connection…"
        )
      }
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return
      }
    }
  }

  private func apply(_ event: HuskyChatEvent) {
    switch event {
    case .sessionReady:
      self.publishStatus("Connected to deterministic local gRPC fixture")
    case .messageAccepted(_, let userMessage, _):
      self.upsert(Self.panelMessage(userMessage))
    case .messageStarted(_, let message):
      self.upsert(Self.panelMessage(message))
    case .textDelta(_, let messageID, _, let append, let replace):
      guard let index = self.messages.firstIndex(where: { $0.id == messageID }) else { return }
      let previous = self.messages[index]
      self.messages[index] = HuskyPanelMessage(
        id: previous.id,
        role: previous.role,
        text: replace ?? previous.text + append
      )
      self.publishMessages()
    case .messageCompleted(_, let message):
      self.upsert(Self.panelMessage(message))
      self.publishStatus("Fixture response complete")
    case .statusChanged(_, let status, let detail):
      self.publishStatus(
        "Fixture status: \(Self.statusName(status))\(detail.isEmpty ? "" : " — \(detail)")")
    case .requestCancelled:
      self.publishStatus("Fixture request cancelled")
    case .requestFailed(_, _, let message, _):
      self.publishStatus("Fixture request failed: \(message)")
    case .resyncRequired(_, _, let reason):
      self.publishStatus("Fixture requested history resynchronization: \(reason)")
    }
  }

  private func upsert(_ message: HuskyPanelMessage) {
    if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
      self.messages[index] = message
    } else {
      self.messages.append(message)
    }
    self.publishMessages()
  }

  private func publishMessages() {
    self.messagesContinuation?.yield(self.messages)
  }

  private func publishStatus(_ status: String?) {
    self.statusText = status
    self.statusContinuation?.yield(status)
  }

  private static func panelMessage(_ message: HuskyMessage) -> HuskyPanelMessage {
    HuskyPanelMessage(
      id: message.id,
      role: message.role == .user ? .user : .backend,
      text: message.text
    )
  }

  private static func statusName(_ status: HuskyCore.HuskyBackendStatus) -> String {
    switch status {
    case .thinking: "Thinking"
    case .typing: "Typing"
    case .waiting: "Waiting"
    case .idle: "Idle"
    case .error: "Error"
    case .unknown(let rawValue): "Unknown (\(rawValue))"
    }
  }
}
