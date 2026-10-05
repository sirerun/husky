import Foundation
import GRPCCore
import GRPCProtobuf
import HuskyProtocol

/// Deterministic in-memory state shared by the fixture service's RPC handlers.
public actor HuskyFixtureStore {
  private struct Submission: Sendable {
    var text: String
    var acceptedMessage: HuskyChatMessage
    var assistantMessage: HuskyChatMessage?
    var isComplete: Bool
    var isCancelled: Bool
    var cancellationEvent: HuskyBackendEvent?
    var generation: Task<Void, Never>?
  }

  private struct Conversation: Sendable {
    var summary: HuskyConversationSummary
    var messages: [HuskyChatMessage] = []
    var events: [HuskyBackendEvent] = []
    var sequence: UInt64 = 0
    var submissions: [String: Submission] = [:]
    var emittedUnsolicitedMessage = false
    var generationTail: Task<Void, Never>?
  }

  private let configuration: HuskyFixtureConfiguration
  private var conversations: [String: Conversation] = [:]
  private var conversationOrder: [String] = []
  private var createRequests: [String: (title: String, conversationID: String)] = [:]
  private var requestOwners: [String: (conversationID: String, text: String)] = [:]
  private var subscribers: [String: [UUID: AsyncStream<HuskyBackendEvent>.Continuation]] = [:]
  private var nextConversationNumber = 1
  private var nextMessageNumber = 1

  public init(configuration: HuskyFixtureConfiguration = .init()) {
    self.configuration = configuration
  }

  func capabilities() -> HuskyGetCapabilitiesResponse {
    .with {
      $0.protocolVersion = "husky.v1"
      $0.minimumClientMajor = 1
      $0.maximumClientMajor = 1
      $0.maximumMessageUtf8Bytes = 65_536
      $0.defaultHistoryPageSize = 50
      $0.maximumHistoryPageSize = 100
      $0.features = ["typed-chat", "stream-resume", "history-pagination", "fixture"]
    }
  }

  func listConversations(_ request: HuskyListConversationsRequest) throws
    -> HuskyListConversationsResponse
  {
    let pageSize = try normalizedPageSize(request.pageSize)
    let end: Int
    if request.beforeCursor.isEmpty {
      end = conversationOrder.count
    } else {
      end = try decodeCursor(request.beforeCursor, prefix: "conversations")
      guard end <= conversationOrder.count else {
        throw rpcError(.invalidArgument, "The conversation cursor is no longer valid.")
      }
    }

    let start = max(0, end - pageSize)
    let summaries = conversationOrder[start..<end].compactMap { conversations[$0]?.summary }
    return .with {
      $0.conversations = summaries
      $0.hasMore = start > 0
      $0.nextCursor = start > 0 ? encodeCursor("conversations", start) : ""
    }
  }

  func createConversation(_ request: HuskyCreateConversationRequest) throws
    -> HuskyCreateConversationResponse
  {
    guard !request.clientRequestID.isEmpty else {
      throw rpcError(.invalidArgument, "client_request_id must not be empty.")
    }
    let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if let previous = createRequests[request.clientRequestID] {
      guard previous.title == title else {
        throw rpcError(.invalidArgument, "client_request_id was reused with different content.")
      }
      guard let conversation = conversations[previous.conversationID] else {
        throw rpcError(.internalError, "The fixture's idempotency record is inconsistent.")
      }
      return .with { $0.conversation = conversation.summary }
    }

    let conversationID = String(format: "fixture-conversation-%04d", nextConversationNumber)
    nextConversationNumber += 1
    let summary = HuskyConversationSummary.with {
      $0.conversationID = conversationID
      $0.title = title.isEmpty ? "Fixture conversation \(nextConversationNumber - 1)" : title
    }
    conversations[conversationID] = Conversation(summary: summary)
    conversationOrder.append(conversationID)
    createRequests[request.clientRequestID] = (title, conversationID)
    return .with { $0.conversation = summary }
  }

  func history(_ request: HuskyGetHistoryRequest) throws -> HuskyGetHistoryResponse {
    guard let conversation = conversations[request.conversationID] else {
      throw rpcError(.failedPrecondition, "The requested fixture conversation does not exist.")
    }
    let pageSize = try normalizedPageSize(request.pageSize)
    let snapshotCount: Int
    let before: Int
    let snapshotSequence: UInt64
    if request.beforeCursor.isEmpty {
      snapshotCount = conversation.messages.count
      before = snapshotCount
      snapshotSequence = conversation.sequence
    } else {
      let cursor = try decodeHistoryCursor(request.beforeCursor)
      guard cursor.conversationID == request.conversationID,
        cursor.snapshotCount <= conversation.messages.count,
        cursor.before <= cursor.snapshotCount,
        cursor.snapshotSequence <= conversation.sequence
      else {
        throw rpcError(
          .invalidArgument, "The history cursor does not match this conversation snapshot.")
      }
      snapshotCount = cursor.snapshotCount
      before = cursor.before
      snapshotSequence = cursor.snapshotSequence
    }

    let start = max(0, before - pageSize)
    let page = Array(conversation.messages[start..<before])
    return .with {
      $0.messages = page
      $0.hasMore = start > 0
      $0.nextCursor =
        start > 0
        ? encodeHistoryCursor(
          conversationID: request.conversationID,
          snapshotCount: snapshotCount,
          before: start,
          snapshotSequence: snapshotSequence
        )
        : ""
      $0.snapshotSequence = snapshotSequence
    }
  }

  func attach(
    conversationID: String,
    afterSequence: UInt64,
    subscriptionID: UUID,
    continuation: AsyncStream<HuskyBackendEvent>.Continuation
  ) throws -> Bool {
    guard var conversation = conversations[conversationID] else {
      throw rpcError(.failedPrecondition, "The requested fixture conversation does not exist.")
    }
    guard afterSequence <= conversation.sequence else {
      throw rpcError(.invalidArgument, "after_sequence is ahead of the fixture event log.")
    }

    let retained = conversation.events
    let oldest = retained.first?.sequence ?? (conversation.sequence + 1)
    if afterSequence < oldest - 1 {
      continuation.yield(
        .with {
          $0.sequence = 0
          $0.resyncRequired = .with {
            $0.conversationID = conversationID
            $0.oldestAvailableSequence = oldest
            $0.reason =
              "The deterministic fixture event window has expired. Fetch history and attach at its snapshot sequence."
          }
        })
      return true
    }

    // Mark the listener before yielding the replay snapshot. Actor isolation
    // makes this subscribe-and-replay operation atomic with event appends.
    subscribers[conversationID, default: [:]][subscriptionID] = continuation
    for event in retained where event.sequence > afterSequence {
      continuation.yield(event)
    }
    let watermark = conversation.sequence
    continuation.yield(
      .with {
        $0.sequence = 0
        $0.sessionReady = .with {
          $0.conversationID = conversationID
          $0.caughtUpThroughSequence = watermark
          $0.resumeToken = resumeToken(conversationID: conversationID, sequence: watermark)
        }
      })

    if configuration.emitUnsolicitedMessageOnFirstAttach, !conversation.emittedUnsolicitedMessage {
      conversation.emittedUnsolicitedMessage = true
      conversations[conversationID] = conversation
      let delay = configuration.responseStepDelay
      Task {
        if delay > .zero { try? await Task.sleep(for: delay) }
        await self.emitUnsolicitedMessage(in: conversationID)
      }
    }
    return false
  }

  func detach(conversationID: String, subscriptionID: UUID) {
    subscribers[conversationID]?.removeValue(forKey: subscriptionID)
    if subscribers[conversationID]?.isEmpty == true {
      subscribers.removeValue(forKey: conversationID)
    }
  }

  func submit(_ request: HuskySubmitMessage, in conversationID: String) throws -> HuskyBackendEvent
  {
    guard var conversation = conversations[conversationID] else {
      throw rpcError(.failedPrecondition, "The requested fixture conversation does not exist.")
    }
    guard request.conversationID == conversationID else {
      throw rpcError(
        .invalidArgument, "The submission conversation does not match the active session.")
    }
    guard !request.requestID.isEmpty else {
      throw rpcError(.invalidArgument, "request_id must not be empty.")
    }
    guard !request.text.isEmpty, request.text.utf8.count <= 65_536 else {
      throw rpcError(.invalidArgument, "Message text must contain 1 through 65536 UTF-8 bytes.")
    }
    if let owner = requestOwners[request.requestID],
      owner.conversationID != conversationID || owner.text != request.text
    {
      throw rpcError(
        .invalidArgument, "request_id was reused with different content or conversation scope.")
    }

    if let previous = conversation.submissions[request.requestID] {
      guard previous.text == request.text else {
        throw rpcError(.invalidArgument, "request_id was reused with different content.")
      }
      return .with {
        $0.sequence = 0
        $0.messageAccepted = .with {
          $0.requestID = request.requestID
          $0.userMessage = previous.acceptedMessage
          $0.replayedIdempotentResult = true
        }
      }
    }

    let userMessageID = nextMessageID()
    let userSequence = conversation.sequence + 1
    let userMessage = HuskyChatMessage.with {
      $0.messageID = userMessageID
      $0.conversationID = conversationID
      $0.role = .user
      $0.text = request.text
      $0.requestID = request.requestID
      $0.sequence = userSequence
    }
    conversation.messages.append(userMessage)
    conversation.submissions[request.requestID] = Submission(
      text: request.text,
      acceptedMessage: userMessage,
      assistantMessage: nil,
      isComplete: false,
      isCancelled: false,
      cancellationEvent: nil
    )
    requestOwners[request.requestID] = (conversationID, request.text)
    conversations[conversationID] = conversation

    let accepted = appendEvent(
      .with {
        $0.messageAccepted = .with {
          $0.requestID = request.requestID
          $0.userMessage = userMessage
          $0.replayedIdempotentResult = false
        }
      },
      to: conversationID
    )
    emitStatus(.thinking, requestID: request.requestID, conversationID: conversationID)
    let delay = configuration.responseStepDelay
    let previousGeneration = conversations[conversationID]?.generationTail
    let generation = Task {
      await previousGeneration?.value
      await self.generateResponse(
        for: request,
        in: conversationID,
        delay: delay
      )
    }
    if var current = conversations[conversationID],
      var submission = current.submissions[request.requestID]
    {
      submission.generation = generation
      current.submissions[request.requestID] = submission
      current.generationTail = generation
      conversations[conversationID] = current
    }
    return accepted
  }

  func cancel(requestID: String, in conversationID: String) throws -> HuskyBackendEvent {
    guard var conversation = conversations[conversationID] else {
      throw rpcError(.failedPrecondition, "The requested fixture conversation does not exist.")
    }
    guard let varSubmission = conversation.submissions[requestID] else {
      throw rpcError(.failedPrecondition, "The request is not known to this fixture conversation.")
    }
    var submission = varSubmission
    guard !submission.isComplete else {
      // Cancellation after completion is an idempotent no-op. The canonical
      // completed message remains available in history.
      return .with { $0.requestCancelled.requestID = requestID }
    }
    if submission.isCancelled {
      return submission.cancellationEvent ?? .with { $0.requestCancelled.requestID = requestID }
    }

    submission.generation?.cancel()
    submission.generation = nil
    submission.isCancelled = true
    conversation.submissions[requestID] = submission
    conversations[conversationID] = conversation
    emitStatus(.idle, requestID: requestID, conversationID: conversationID)
    let cancelled = appendEvent(
      .with {
        $0.requestCancelled.requestID = requestID
      }, to: conversationID)
    if var latest = conversations[conversationID], var updated = latest.submissions[requestID] {
      updated.cancellationEvent = cancelled
      latest.submissions[requestID] = updated
      conversations[conversationID] = latest
    }
    return cancelled
  }

  private func generateResponse(
    for request: HuskySubmitMessage, in conversationID: String, delay: Duration
  ) async {
    do {
      try await pause(delay)
      guard let initial = conversations[conversationID],
        let submission = initial.submissions[request.requestID], !submission.isComplete,
        !submission.isCancelled
      else {
        return
      }
      let assistantMessageID = nextMessageID()
      let startedSequence = initial.sequence + 1
      let assistant = HuskyChatMessage.with {
        $0.messageID = assistantMessageID
        $0.conversationID = conversationID
        $0.role = .assistant
        $0.requestID = request.requestID
        $0.sequence = startedSequence
      }
      updateSubmission(request.requestID, in: conversationID) { $0.assistantMessage = assistant }
      _ = appendEvent(
        .with {
          $0.messageStarted = .with {
            $0.requestID = request.requestID
            $0.message = assistant
          }
        },
        to: conversationID
      )

      let reply = "Fixture response: \(request.text)"
      let split = reply.index(reply.startIndex, offsetBy: min(16, reply.count))
      let pieces = [String(reply[..<split]), String(reply[split...])].filter { !$0.isEmpty }
      var accumulated = ""
      for (index, piece) in pieces.enumerated() {
        try await pause(delay)
        guard let current = conversations[conversationID],
          let active = current.submissions[request.requestID], !active.isComplete,
          !active.isCancelled
        else { return }
        accumulated += piece
        _ = appendEvent(
          .with {
            $0.textDelta = .with {
              $0.requestID = request.requestID
              $0.messageID = assistantMessageID
              $0.revision = UInt64(index + 1)
              $0.appendText = piece
            }
          },
          to: conversationID
        )
      }

      try await pause(delay)
      guard let latest = conversations[conversationID],
        let active = latest.submissions[request.requestID], !active.isComplete, !active.isCancelled
      else { return }
      var completed = assistant
      completed.text = accumulated
      completed.sequence = latest.sequence + 1
      updateSubmission(request.requestID, in: conversationID) {
        $0.assistantMessage = completed
        $0.isComplete = true
        $0.generation = nil
      }
      if var finalRecord = conversations[conversationID] {
        finalRecord.messages.append(completed)
        conversations[conversationID] = finalRecord
      }
      _ = appendEvent(
        .with {
          $0.messageCompleted = .with {
            $0.requestID = request.requestID
            $0.message = completed
          }
        },
        to: conversationID
      )
      emitStatus(.idle, requestID: request.requestID, conversationID: conversationID)
    } catch is CancellationError {
      // The cancellation command already emitted the canonical cancellation event.
    } catch {
      let failed = HuskyBackendEvent.with {
        $0.sequence = 0
        $0.requestFailed = .with {
          $0.requestID = request.requestID
          $0.publicCode = "FIXTURE_FAILURE"
          $0.message = "The deterministic fixture script failed."
          $0.retryable = false
        }
      }
      publish(failed, to: conversationID)
    }
  }

  private func emitUnsolicitedMessage(in conversationID: String) {
    guard let conversation = conversations[conversationID] else { return }
    let messageID = nextMessageID()
    let started = HuskyChatMessage.with {
      $0.messageID = messageID
      $0.conversationID = conversationID
      $0.role = .assistant
      $0.text = ""
      $0.sequence = conversation.sequence + 1
    }
    _ = appendEvent(
      .with { $0.messageStarted.message = started },
      to: conversationID
    )
    let finalText = "Fixture initiated this message without a client request."
    _ = appendEvent(
      .with {
        $0.textDelta = .with {
          $0.messageID = messageID
          $0.revision = 1
          $0.appendText = finalText
        }
      },
      to: conversationID
    )
    let final = HuskyChatMessage.with {
      $0.messageID = messageID
      $0.conversationID = conversationID
      $0.role = .assistant
      $0.text = finalText
      $0.sequence = (conversations[conversationID]?.sequence ?? 0) + 1
    }
    if var current = conversations[conversationID] {
      current.messages.append(final)
      conversations[conversationID] = current
    }
    _ = appendEvent(.with { $0.messageCompleted.message = final }, to: conversationID)
  }

  private func updateSubmission(
    _ requestID: String, in conversationID: String, update: (inout Submission) -> Void
  ) {
    guard var conversation = conversations[conversationID],
      var submission = conversation.submissions[requestID]
    else { return }
    update(&submission)
    conversation.submissions[requestID] = submission
    conversations[conversationID] = conversation
  }

  private func emitStatus(_ status: HuskyBackendStatus, requestID: String, conversationID: String) {
    _ = appendEvent(
      .with {
        $0.statusChanged = .with {
          $0.requestID = requestID
          $0.status = status
          $0.detail = "Local deterministic fixture status."
        }
      }, to: conversationID)
  }

  private func appendEvent(_ event: HuskyBackendEvent, to conversationID: String)
    -> HuskyBackendEvent
  {
    guard var conversation = conversations[conversationID] else { return event }
    conversation.sequence += 1
    var event = event
    event.sequence = conversation.sequence
    conversation.events.append(event)
    if conversation.events.count > configuration.retainedEventLimit {
      conversation.events.removeFirst(conversation.events.count - configuration.retainedEventLimit)
    }
    conversations[conversationID] = conversation
    publish(event, to: conversationID)
    return event
  }

  private func publish(_ event: HuskyBackendEvent, to conversationID: String) {
    if let continuations = subscribers[conversationID]?.values {
      for continuation in continuations {
        continuation.yield(event)
      }
    }
  }

  private func pause(_ duration: Duration) async throws {
    if duration > .zero { try await Task.sleep(for: duration) }
    try Task.checkCancellation()
  }

  private func normalizedPageSize(_ requested: UInt32) throws -> Int {
    let size = requested == 0 ? 50 : Int(requested)
    guard size <= 100 else { throw rpcError(.invalidArgument, "page_size cannot exceed 100.") }
    return max(1, size)
  }

  private func nextMessageID() -> String {
    defer { nextMessageNumber += 1 }
    return String(format: "fixture-message-%06d", nextMessageNumber)
  }

  private func resumeToken(conversationID: String, sequence: UInt64) -> String {
    "fixture-v1:\(conversationID):\(sequence)"
  }

  private func encodeCursor(_ kind: String, _ offset: Int) -> String {
    "fixture-v1:\(kind):\(offset)"
  }

  private func decodeCursor(_ cursor: String, prefix: String) throws -> Int {
    let parts = cursor.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "fixture-v1", parts[1] == Substring(prefix),
      let offset = Int(parts[2]), offset >= 0
    else { throw rpcError(.invalidArgument, "The fixture cursor is malformed.") }
    return offset
  }

  private func encodeHistoryCursor(
    conversationID: String, snapshotCount: Int, before: Int, snapshotSequence: UInt64
  ) -> String {
    "fixture-v1:history:\(conversationID):\(snapshotCount):\(before):\(snapshotSequence)"
  }

  private func decodeHistoryCursor(_ cursor: String) throws -> (
    conversationID: String, snapshotCount: Int, before: Int, snapshotSequence: UInt64
  ) {
    let parts = cursor.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 6, parts[0] == "fixture-v1", parts[1] == "history",
      let snapshotCount = Int(parts[3]), snapshotCount >= 0,
      let before = Int(parts[4]), before >= 0,
      let snapshotSequence = UInt64(parts[5])
    else { throw rpcError(.invalidArgument, "The history cursor is malformed.") }
    return (String(parts[2]), snapshotCount, before, snapshotSequence)
  }

  private func rpcError(_ code: RPCError.Code, _ message: String) -> RPCError {
    RPCError(code: code, message: message)
  }
}
