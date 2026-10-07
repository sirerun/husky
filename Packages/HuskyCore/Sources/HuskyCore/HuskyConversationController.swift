import Foundation
import Observation

public enum HuskySubmissionResult: Sendable, Equatable {
  case accepted
  case rejected
  case unconfirmed
}

/// Coordinates the selected backend conversation without owning durable history.
/// Every operation is scoped to a generation so late network results cannot
/// mutate a newly selected profile or conversation.
@MainActor @Observable public final class HuskyConversationController {
  public private(set) var messages: [HuskyMessage] = []
  public private(set) var conversations: [HuskyConversation] = []
  public private(set) var selectedConversationID: String?
  public private(set) var hasMoreHistory = false
  public private(set) var hasMoreConversations = false
  public private(set) var isLoading = false
  public private(set) var isLoadingHistory = false
  public private(set) var isConnected = false
  public private(set) var statusText: String?
  public private(set) var activeRequestID: String?

  private struct RequestKey: Hashable, Sendable {
    let profileID: UUID
    let conversationID: String
    let requestID: String
  }

  private struct AcceptanceWaiter {
    let key: RequestKey
    let continuation: CheckedContinuation<HuskySubmissionResult, Never>
    var timeoutTask: Task<Void, Never>?
  }

  private struct PendingConversationCreate: Sendable {
    let requestID: String
    let title: String
  }

  private enum TimeoutError: Error {
    case elapsed
  }

  private var client: (any HuskyChatClient)?
  private var profileID: UUID?
  private var capabilities: HuskyCapabilities?
  private var session: (any HuskyConversationSession)?
  private var eventTask: Task<Void, Never>?
  private var cursor: HuskyEventCursor?
  private var generation: UInt64 = 0
  private var historySnapshotSequence: UInt64 = 0
  private var historyCursor: String?
  private var conversationCursor: String?
  private var seenHistoryCursors: Set<String> = []
  private var seenConversationCursors: Set<String> = []
  private var historyPageSize: UInt32 = 50
  private var conversationPageSize: UInt32 = 50
  private var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
  private var requestPayloads: [RequestKey: String] = [:]
  private var acceptedRequests: Set<RequestKey> = []
  private var completedRequests: Set<RequestKey> = []
  private var failedBeforeAcceptance: Set<RequestKey> = []
  private var acceptanceWaiters: [UUID: AcceptanceWaiter] = [:]
  private var inFlightSubmissions: Set<RequestKey> = []
  private var recoveryAttempts = 0
  // Retained after an ambiguous create so retries reuse the original idempotency key.
  // This intent is volatile; a persisted-create contract would be needed across app restarts.
  private var pendingConversationCreate: PendingConversationCreate?

  private let operationTimeout: Duration
  private let acceptanceTimeout: Duration
  private let cleanupTimeout: Duration

  public convenience init() {
    self.init(
      operationTimeout: .seconds(8), acceptanceTimeout: .seconds(12), cleanupTimeout: .seconds(1))
  }

  init(
    operationTimeout: Duration,
    acceptanceTimeout: Duration,
    cleanupTimeout: Duration
  ) {
    self.operationTimeout = operationTimeout
    self.acceptanceTimeout = acceptanceTimeout
    self.cleanupTimeout = cleanupTimeout
  }

  public func attach(
    profileID: UUID,
    client: any HuskyChatClient,
    preferredConversationID: String? = nil
  ) async {
    let (newGeneration, oldSession) = beginNewScope()
    self.client = client
    self.profileID = profileID
    self.isLoading = true
    self.statusText = "Connecting…"
    await finishSession(oldSession)
    guard self.generation == newGeneration else { return }

    do {
      let fetchedCapabilities = try await self.bounded(self.operationTimeout) {
        try await client.getCapabilities()
      }
      guard self.generation == newGeneration else { return }
      self.capabilities = fetchedCapabilities
      self.historyPageSize = Self.pageSize(
        preferred: fetchedCapabilities.defaultHistoryPageSize,
        maximum: fetchedCapabilities.maximumHistoryPageSize)
      self.conversationPageSize = max(1, min(50, fetchedCapabilities.maximumHistoryPageSize))
      let initialConversationPageSize = self.conversationPageSize

      let page = try await self.bounded(self.operationTimeout) {
        try await client.listConversations(pageSize: initialConversationPageSize, before: nil)
      }
      guard self.generation == newGeneration else { return }
      self.conversations = Self.uniqueConversations(page.conversations)
      self.conversationCursor = page.nextCursor
      self.seenConversationCursors = page.nextCursor.map { [$0] } ?? []
      self.hasMoreConversations = page.hasMore && page.nextCursor != nil
      self.isLoading = false
      self.isConnected = true
      self.statusText = nil

      var selectedID = preferredConversationID.flatMap { preferred in
        self.conversations.contains(where: { $0.id == preferred }) ? preferred : nil
      }
      var preferredHistory: HuskyHistoryPage?
      var cursor = page.nextCursor
      var mayHaveMore = page.hasMore
      var requestedCursors: Set<String> = []
      var pagesRead = 0
      while selectedID == nil, preferredConversationID != nil, mayHaveMore,
        let next = cursor, pagesRead < 24
      {
        guard requestedCursors.insert(next).inserted else {
          self.statusText = "The backend returned a repeated conversation cursor."
          mayHaveMore = false
          break
        }
        let pageSize = self.conversationPageSize
        let nextPage = try await self.bounded(self.operationTimeout) {
          try await client.listConversations(pageSize: pageSize, before: next)
        }
        guard self.generation == newGeneration else { return }
        for conversation in nextPage.conversations {
          self.upsertConversation(conversation, preferIncoming: false)
        }
        selectedID = preferredConversationID.flatMap { preferred in
          self.conversations.contains(where: { $0.id == preferred }) ? preferred : nil
        }
        if let nextCursor = nextPage.nextCursor {
          if self.seenConversationCursors.contains(nextCursor) {
            self.statusText = "The backend returned a repeated conversation cursor."
            mayHaveMore = false
          } else {
            self.seenConversationCursors.insert(nextCursor)
            cursor = nextCursor
            mayHaveMore = nextPage.hasMore
          }
        } else {
          cursor = nil
          mayHaveMore = false
        }
        pagesRead += 1
      }
      self.conversationCursor = cursor
      self.hasMoreConversations = mayHaveMore && cursor != nil

      // A saved conversation may be older than the bounded list scan. A direct
      // history read validates that ID without creating or mutating anything.
      if selectedID == nil, let preferredConversationID, self.hasMoreConversations {
        do {
          let pageSize = self.historyPageSize
          let history = try await self.bounded(self.operationTimeout) {
            try await client.getHistory(
              conversationID: preferredConversationID, pageSize: pageSize, before: nil)
          }
          guard self.generation == newGeneration else { return }
          selectedID = preferredConversationID
          preferredHistory = history
          let dates = history.messages.map(\.createdAt)
          self.upsertConversation(
            HuskyConversation(
              id: preferredConversationID, title: preferredConversationID,
              createdAt: dates.min() ?? .distantPast,
              updatedAt: dates.max() ?? .distantPast), preferIncoming: false)
        } catch {
          // The preferred ID was not accessible; choose from the loaded list.
        }
      }
      selectedID = selectedID ?? self.conversations.first?.id
      guard let selectedID else {
        self.selectedConversationID = nil
        self.statusText = "Connected. Create a conversation to begin."
        return
      }
      await self.activateConversation(
        selectedID, generation: newGeneration, preloadedHistory: preferredHistory)
    } catch {
      guard self.generation == newGeneration else { return }
      self.isLoading = false
      self.isConnected = false
      self.statusText = Self.safeMessage(for: error, operation: "connect")
    }
  }

  public func detach() async {
    let (newGeneration, oldSession) = beginNewScope()
    self.client = nil
    self.profileID = nil
    self.capabilities = nil
    self.conversations = []
    self.selectedConversationID = nil
    self.messages = []
    self.hasMoreHistory = false
    self.hasMoreConversations = false
    self.isLoading = false
    self.isLoadingHistory = false
    self.isConnected = false
    self.statusText = nil
    self.activeRequestID = nil
    self.conversationCursor = nil
    self.historyCursor = nil
    self.cursor = nil
    self.partialMessages = [:]
    self.historySnapshotSequence = 0
    self.resolveAllWaiters(.unconfirmed)
    self.clearRequestState()
    await self.finishSession(oldSession)
    guard self.generation == newGeneration else { return }
  }

  public func selectConversation(id: String) async {
    guard self.conversations.contains(where: { $0.id == id }) else {
      self.statusText = "That conversation is unavailable."
      return
    }
    guard self.selectedConversationID != id || self.session == nil else { return }

    let (newGeneration, oldSession) = self.beginConversationSwitch(to: id)
    await self.finishSession(oldSession)
    guard self.generation == newGeneration else { return }
    await self.activateConversation(id, generation: newGeneration)
  }

  public func createConversation(title: String) async {
    guard let client = self.client else {
      self.statusText = "Connect to a backend before creating a conversation."
      return
    }
    let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTitle.isEmpty else {
      self.statusText = "Enter a conversation title."
      return
    }
    if let pending = self.pendingConversationCreate, pending.title != cleanedTitle {
      self.statusText =
        "Retry the pending conversation create with the same title before changing it."
      return
    }
    let requestID = self.pendingConversationCreate?.requestID ?? UUID().uuidString.lowercased()
    self.pendingConversationCreate = PendingConversationCreate(
      requestID: requestID, title: cleanedTitle)
    let currentGeneration = self.generation
    self.isLoading = true
    self.statusText = nil
    do {
      let conversation = try await self.bounded(self.operationTimeout) {
        try await client.createConversation(requestID: requestID, title: cleanedTitle)
      }
      guard self.generation == currentGeneration else { return }
      self.pendingConversationCreate = nil
      self.upsertConversation(conversation, preferIncoming: true)
      self.isLoading = false
      await self.selectConversation(id: conversation.id)
    } catch {
      guard self.generation == currentGeneration else { return }
      self.isLoading = false
      self.statusText = Self.safeMessage(for: error, operation: "create conversation")
    }
  }

  public func loadOlderMessages() async {
    guard !self.isLoadingHistory,
      self.hasMoreHistory,
      let client = self.client,
      let conversationID = self.selectedConversationID,
      let before = self.historyCursor
    else { return }

    let currentGeneration = self.generation
    let snapshot = self.historySnapshotSequence
    let pageSize = self.historyPageSize
    self.isLoadingHistory = true
    defer {
      if self.generation == currentGeneration { self.isLoadingHistory = false }
    }
    do {
      let page = try await self.bounded(self.operationTimeout) {
        try await client.getHistory(
          conversationID: conversationID, pageSize: pageSize, before: before)
      }
      guard self.generation == currentGeneration,
        self.selectedConversationID == conversationID
      else { return }
      guard self.historySnapshotSequence == snapshot, self.historyCursor == before else {
        self.statusText = "History changed while loading. Reconnect to refresh it."
        return
      }
      guard page.snapshotSequence == snapshot else {
        self.statusText = "History changed while loading. Reconnect to refresh it."
        self.hasMoreHistory = false
        return
      }
      if let nextCursor = page.nextCursor, self.seenHistoryCursors.contains(nextCursor) {
        self.statusText = "The backend returned an invalid history cursor."
        self.hasMoreHistory = false
        return
      }
      self.mergeOlderPage(page.messages)
      self.historyCursor = page.nextCursor
      if let nextCursor = page.nextCursor { self.seenHistoryCursors.insert(nextCursor) }
      self.hasMoreHistory = page.hasMore && page.nextCursor != nil
    } catch {
      guard self.generation == currentGeneration else { return }
      self.statusText = Self.safeMessage(for: error, operation: "load history")
    }
  }

  public func loadMoreConversations() async {
    guard !self.isLoading,
      self.hasMoreConversations,
      let client = self.client,
      let before = self.conversationCursor
    else { return }

    let currentGeneration = self.generation
    let pageSize = self.conversationPageSize
    self.isLoading = true
    defer {
      if self.generation == currentGeneration { self.isLoading = false }
    }
    do {
      let page = try await self.bounded(self.operationTimeout) {
        try await client.listConversations(pageSize: pageSize, before: before)
      }
      guard self.generation == currentGeneration else { return }
      if let nextCursor = page.nextCursor, self.seenConversationCursors.contains(nextCursor) {
        self.statusText = "The backend returned an invalid conversation cursor."
        self.hasMoreConversations = false
        return
      }
      for conversation in page.conversations {
        self.upsertConversation(conversation, preferIncoming: false)
      }
      self.conversationCursor = page.nextCursor
      if let nextCursor = page.nextCursor { self.seenConversationCursors.insert(nextCursor) }
      self.hasMoreConversations = page.hasMore && page.nextCursor != nil
    } catch {
      guard self.generation == currentGeneration else { return }
      self.statusText = Self.safeMessage(for: error, operation: "load conversations")
    }
  }

  /// Sends a stable caller-owned request and waits for its matching
  /// `messageAccepted` event. A successful command enqueue alone is not
  /// acceptance; a timeout leaves the request ID and payload available for an
  /// idempotent retry with exactly the same text.
  public func submit(text: String, requestID: String) async -> Bool {
    await self.submitResult(text: text, requestID: requestID) == .accepted
  }

  public func submitResult(text: String, requestID: String) async -> HuskySubmissionResult {
    guard !requestID.isEmpty, requestID.utf8.count <= 256 else {
      self.statusText = "The request could not be identified."
      return .rejected
    }
    guard let capabilities = self.capabilities else {
      self.statusText = "Connect to a conversation before sending."
      return .unconfirmed
    }
    let bytes = text.utf8.count
    guard bytes <= Int(capabilities.maximumMessageUTF8Bytes) else {
      self.statusText = "This message is too long."
      return .rejected
    }
    guard self.client != nil,
      let session = self.session,
      let profileID = self.profileID,
      let conversationID = self.selectedConversationID
    else {
      self.statusText = "Connect to a conversation before sending."
      return .unconfirmed
    }

    let currentGeneration = self.generation
    let key = RequestKey(
      profileID: profileID, conversationID: conversationID, requestID: requestID)
    if let priorText = self.requestPayloads[key], priorText != text {
      self.statusText = "This request ID is already associated with different text."
      return self.completedRequests.contains(key) ? .rejected : .unconfirmed
    }
    if let activeRequestID, activeRequestID != requestID {
      self.statusText = "Wait for the current reply to finish before sending another message."
      return .rejected
    }
    self.requestPayloads[key] = text
    self.failedBeforeAcceptance.remove(key)

    if !self.acceptedRequests.contains(key), !self.inFlightSubmissions.contains(key) {
      self.inFlightSubmissions.insert(key)
      do {
        _ = try await self.bounded(self.operationTimeout) {
          try await session.submit(requestID: requestID, text: text)
          return true
        }
      } catch {
        guard self.generation == currentGeneration else { return .unconfirmed }
        self.inFlightSubmissions.remove(key)
        if self.acceptedRequests.contains(key) { return .accepted }
        if self.failedBeforeAcceptance.contains(key) { return .rejected }
        self.statusText =
          "The backend has not confirmed this message. Retry with the same request ID and text."
        return .unconfirmed
      }
      guard self.generation == currentGeneration else { return .unconfirmed }
      self.inFlightSubmissions.remove(key)
    }

    if self.acceptedRequests.contains(key) { return .accepted }
    if self.failedBeforeAcceptance.contains(key) { return .rejected }
    return await self.waitForAcceptance(key, generation: currentGeneration)
  }

  public func cancelActiveRequest() async {
    guard let requestID = self.activeRequestID,
      let session = self.session
    else { return }
    let currentGeneration = self.generation
    do {
      _ = try await self.bounded(self.operationTimeout) {
        try await session.cancel(requestID: requestID)
        return true
      }
    } catch {
      guard self.generation == currentGeneration else { return }
      self.statusText = "The cancellation request could not be confirmed."
    }
  }

  public func reconnect() async {
    guard let client = self.client,
      let conversationID = self.selectedConversationID
    else {
      self.statusText = "Select a conversation before reconnecting."
      return
    }
    let (newGeneration, oldSession) = self.beginReconnect()
    await self.finishSession(oldSession)
    guard self.generation == newGeneration else { return }
    await self.openResumedStream(
      client: client, conversationID: conversationID, generation: newGeneration)
  }

  private func beginNewScope() -> (UInt64, (any HuskyConversationSession)?) {
    self.generation &+= 1
    let old = self.session
    self.session = nil
    self.eventTask?.cancel()
    self.eventTask = nil
    self.resolveAllWaiters(.unconfirmed)
    self.clearRequestState()
    self.pendingConversationCreate = nil
    self.recoveryAttempts = 0
    self.isConnected = false
    self.isLoading = false
    self.isLoadingHistory = false
    self.activeRequestID = nil
    self.cursor = nil
    self.partialMessages = [:]
    self.historyCursor = nil
    self.conversationCursor = nil
    self.seenHistoryCursors = []
    self.seenConversationCursors = []
    self.messages = []
    self.conversations = []
    self.selectedConversationID = nil
    self.hasMoreHistory = false
    self.hasMoreConversations = false
    return (self.generation, old)
  }

  private func beginConversationSwitch(to id: String) -> (
    UInt64, (any HuskyConversationSession)?
  ) {
    self.generation &+= 1
    let old = self.session
    self.session = nil
    self.eventTask?.cancel()
    self.eventTask = nil
    self.resolveAllWaiters(.unconfirmed)
    self.clearRequestState()
    self.recoveryAttempts = 0
    self.selectedConversationID = id
    self.messages = []
    self.hasMoreHistory = false
    self.historyCursor = nil
    self.historySnapshotSequence = 0
    self.partialMessages = [:]
    self.cursor = nil
    self.activeRequestID = nil
    self.isConnected = false
    self.isLoading = true
    self.isLoadingHistory = false
    self.statusText = "Loading conversation…"
    return (self.generation, old)
  }

  private func beginReconnect() -> (UInt64, (any HuskyConversationSession)?) {
    self.generation &+= 1
    let old = self.session
    self.session = nil
    self.eventTask?.cancel()
    self.eventTask = nil
    self.resolveAllWaiters(.unconfirmed)
    self.recoveryAttempts = 0
    self.isLoadingHistory = false
    self.inFlightSubmissions = []
    self.isConnected = false
    self.isLoading = true
    self.statusText = "Reconnecting…"
    return (self.generation, old)
  }

  private func activateConversation(
    _ id: String, generation: UInt64, preloadedHistory: HuskyHistoryPage? = nil
  ) async {
    guard let client = self.client else { return }
    let pageSize = self.historyPageSize
    self.selectedConversationID = id
    self.isLoading = true
    self.isConnected = false
    self.statusText = "Loading conversation…"
    do {
      let page: HuskyHistoryPage
      if let preloadedHistory {
        page = preloadedHistory
      } else {
        page = try await self.bounded(self.operationTimeout) {
          try await client.getHistory(conversationID: id, pageSize: pageSize, before: nil)
        }
      }
      guard self.generation == generation, self.selectedConversationID == id else { return }
      self.messages = Self.uniqueMessages(page.messages)
      self.historyCursor = page.nextCursor
      self.seenHistoryCursors = page.nextCursor.map { [$0] } ?? []
      self.hasMoreHistory = page.hasMore && page.nextCursor != nil
      self.historySnapshotSequence = page.snapshotSequence
      self.cursor = HuskyEventCursor(conversationID: id, afterSequence: page.snapshotSequence)
      try self.installPartialMessages(
        page.partialMessages, conversationID: id, afterSequence: page.snapshotSequence)
      self.isLoading = false
      await self.openResumedStream(client: client, conversationID: id, generation: generation)
    } catch {
      guard self.generation == generation else { return }
      self.isLoading = false
      self.isConnected = false
      self.statusText = Self.safeMessage(for: error, operation: "load conversation")
    }
  }

  private func openResumedStream(
    client: any HuskyChatClient,
    conversationID: String,
    generation: UInt64
  ) async {
    guard let cursor = self.cursor,
      cursor.conversationID == conversationID,
      self.generation == generation
    else { return }
    do {
      let partialSnapshots = try self.partialSnapshotsForResume(
        conversationID: conversationID, afterSequence: cursor.lastAppliedSequence)
      let opened = try await self.bounded(self.operationTimeout) {
        try await client.openConversation(
          conversationID: conversationID,
          afterSequence: cursor.lastAppliedSequence,
          resumeToken: cursor.resumeToken,
          partialMessages: partialSnapshots)
      }
      guard self.generation == generation, self.selectedConversationID == conversationID else {
        await self.finishSession(opened)
        return
      }
      self.session = opened
      self.isLoading = false
      self.startEventConsumer(
        opened, client: client, conversationID: conversationID, generation: generation)
    } catch {
      guard self.generation == generation else { return }
      self.isLoading = false
      self.isConnected = false
      self.statusText = Self.isUnsupportedPartialRecoveryAdapter(error)
        ? "The in-progress reply cannot be resumed safely by this client. Reconnect after it finishes or select another conversation."
        : "The conversation could not reconnect. Select Reconnect to try again."
    }
  }

  private func startEventConsumer(
    _ session: any HuskyConversationSession,
    client: any HuskyChatClient,
    conversationID: String,
    generation: UInt64
  ) {
    self.eventTask?.cancel()
    self.eventTask = Task { @MainActor [weak self, session, client] in
      guard let self else { return }
      await self.consumeEvents(
        from: session, client: client, conversationID: conversationID, generation: generation)
    }
  }

  private func consumeEvents(
    from session: any HuskyConversationSession,
    client: any HuskyChatClient,
    conversationID: String,
    generation: UInt64
  ) async {
    do {
      for try await sequencedEvent in session.events {
        guard !Task.isCancelled,
          self.generation == generation,
          self.selectedConversationID == conversationID
        else { return }
        guard var cursor = self.cursor else { return }
        let disposition = try cursor.stage(sequencedEvent)
        switch disposition {
        case .ignoreDuplicate:
          continue
        case .resynchronize:
          self.cursor = cursor
          await self.recoverFromStream(
            client: client, conversationID: conversationID, generation: generation,
            refreshHistory: true)
          return
        case .deliver:
          let previousSequence = cursor.lastAppliedSequence
          try self.apply(sequencedEvent, conversationID: conversationID)
          try cursor.acknowledge(sequencedEvent)
          guard self.generation == generation else { return }
          self.cursor = cursor
          if case .sessionReady = sequencedEvent.event {
            self.isConnected = true
            self.statusText = nil
          } else if sequencedEvent.sequence > previousSequence {
            self.recoveryAttempts = 0
          }
        }
      }
      guard !Task.isCancelled, self.generation == generation else { return }
      await self.recoverFromStream(
        client: client, conversationID: conversationID, generation: generation,
        refreshHistory: false)
    } catch {
      guard !Task.isCancelled, self.generation == generation else { return }
      if Self.isMissingPartialMessageBaseline(error) {
        await self.stopAfterUnseededPartialMessage(
          session: session, conversationID: conversationID, generation: generation)
        return
      }
      await self.recoverFromStream(
        client: client, conversationID: conversationID, generation: generation,
        refreshHistory: false)
    }
  }

  private func apply(_ sequenced: HuskySequencedEvent, conversationID: String) throws {
    let event = sequenced.event
    let maxBytes = self.capabilities?.maximumMessageUTF8Bytes ?? UInt32.max
    try HuskyMessageBodyValidator.apply(
      event, maximumBytes: maxBytes, expectedConversationID: conversationID,
      partialMessages: &self.partialMessages)

    switch event {
    case .sessionReady:
      break

    case .messageAccepted(let requestID, let message, let replayed):
      self.upsertEventMessage(message)
      if !replayed { self.activeRequestID = requestID }
      guard let profileID = self.profileID else { return }
      let key = RequestKey(
        profileID: profileID, conversationID: conversationID, requestID: requestID)
      self.acceptedRequests.insert(key)
      self.failedBeforeAcceptance.remove(key)
      self.resolveWaiters(for: key, result: .accepted)
      self.statusText = "Message accepted."

    case .messageStarted(let requestID, let message):
      self.upsertEventMessage(message)
      if let requestID { self.activeRequestID = requestID }

    case .textDelta(let requestID, let messageID, _, _, _):
      guard let partial = self.partialMessages[messageID],
        let index = self.messages.firstIndex(where: { $0.id == messageID })
      else {
        throw HuskyClientError.malformedResponse("text delta references an unknown message")
      }
      let previous = self.messages[index]
      self.messages[index] = HuskyMessage(
        id: previous.id, conversationID: previous.conversationID, role: previous.role,
        text: partial.text, createdAt: previous.createdAt,
        requestID: requestID ?? previous.requestID, sequence: sequenced.sequence)
      if let requestID { self.activeRequestID = requestID }

    case .messageCompleted(_, let message):
      self.upsertEventMessage(message)
      if self.activeRequestID == message.requestID { self.activeRequestID = nil }
      self.finishRequest(message.requestID, conversationID: conversationID)
      self.statusText = nil

    case .statusChanged(_, let status, let detail):
      self.statusText = detail.isEmpty ? Self.statusLabel(status) : detail

    case .requestCancelled(let requestID):
      if self.activeRequestID == requestID { self.activeRequestID = nil }
      self.finishRequest(requestID, conversationID: conversationID)
      self.statusText = "Request canceled."

    case .requestFailed(let requestID, _, let message, _):
      if self.activeRequestID == requestID { self.activeRequestID = nil }
      guard let profileID = self.profileID else { return }
      let key = RequestKey(
        profileID: profileID, conversationID: conversationID, requestID: requestID)
      if !self.acceptedRequests.contains(key) {
        self.failedBeforeAcceptance.insert(key)
        self.resolveWaiters(for: key, result: .rejected)
      }
      self.finishRequest(requestID, conversationID: conversationID)
      self.statusText = message.isEmpty ? "The backend could not complete this request." : message

    case .resyncRequired:
      break
    }
    self.messages.sort(by: Self.messageOrder)
  }

  private func recoverFromStream(
    client: any HuskyChatClient,
    conversationID: String,
    generation: UInt64,
    refreshHistory: Bool
  ) async {
    guard self.generation == generation,
      self.selectedConversationID == conversationID
    else { return }
    self.isConnected = false
    self.statusText = "Reconnecting…"
    self.recoveryAttempts += 1
    guard self.recoveryAttempts <= 3 else {
      self.statusText = "The connection was interrupted. Select Reconnect to try again."
      return
    }
    let old = self.session
    self.session = nil
    await self.finishSession(old)
    guard self.generation == generation else { return }

    if refreshHistory {
      let pageSize = self.historyPageSize
      do {
        let page = try await self.bounded(self.operationTimeout) {
          try await client.getHistory(
            conversationID: conversationID, pageSize: pageSize, before: nil)
        }
        guard self.generation == generation else { return }
        try self.mergeCanonicalSnapshot(page, conversationID: conversationID)
      } catch {
        guard self.generation == generation else { return }
        self.statusText =
          "The conversation could not refresh after a stream gap. Select Reconnect to try again."
        return
      }
    }

    guard self.generation == generation else { return }
    let delay = Duration.milliseconds(Int64(250 * (1 << (self.recoveryAttempts - 1))))
    do { try await Task.sleep(for: delay) } catch { return }
    guard self.generation == generation else { return }
    await self.openResumedStream(
      client: client, conversationID: conversationID, generation: generation)
  }

  private func mergeCanonicalSnapshot(
    _ page: HuskyHistoryPage, conversationID: String
  ) throws {
    let snapshot = page.snapshotSequence
    let seededPartials = try HuskyMessageBodyValidator.seed(
      page.partialMessages, conversationID: conversationID, afterSequence: snapshot,
      maximumBytes: self.capabilities?.maximumMessageUTF8Bytes ?? UInt32.max)
    var byID = Dictionary(
      uniqueKeysWithValues: self.messages.filter { $0.sequence <= snapshot }.map { ($0.id, $0) })
    for message in page.messages {
      byID[message.id] = message
    }
    let pageIDs = Set(page.messages.map(\.id))
    for oldID in self.partialMessages.keys where seededPartials[oldID] == nil && !pageIDs.contains(oldID) {
      byID.removeValue(forKey: oldID)
    }
    for partial in page.partialMessages {
      byID[partial.message.id] = partial.message
    }
    self.messages = byID.values.sorted(by: Self.messageOrder)
    self.historySnapshotSequence = snapshot
    self.historyCursor = page.nextCursor
    self.seenHistoryCursors = page.nextCursor.map { [$0] } ?? []
    self.hasMoreHistory = page.hasMore && page.nextCursor != nil
    self.cursor?.reset(after: snapshot, resumeToken: nil)
    self.partialMessages = seededPartials
  }

  private func installPartialMessages(
    _ snapshots: [HuskyPartialMessageSnapshot], conversationID: String, afterSequence: UInt64
  ) throws {
    let seeded = try HuskyMessageBodyValidator.seed(
      snapshots, conversationID: conversationID, afterSequence: afterSequence,
      maximumBytes: self.capabilities?.maximumMessageUTF8Bytes ?? UInt32.max)
    var byID = Dictionary(uniqueKeysWithValues: self.messages.map { ($0.id, $0) })
    for snapshot in snapshots {
      byID[snapshot.message.id] = snapshot.message
    }
    self.messages = byID.values.sorted(by: Self.messageOrder)
    self.partialMessages = seeded
  }

  private func partialSnapshotsForResume(
    conversationID: String, afterSequence: UInt64
  ) throws -> [HuskyPartialMessageSnapshot] {
    let snapshots = try self.partialMessages.map { id, partial -> HuskyPartialMessageSnapshot in
      guard let message = self.messages.first(where: { $0.id == id }) else {
        throw HuskyClientError.malformedResponse("partial message is missing from displayed history")
      }
      return HuskyPartialMessageSnapshot(
        message: HuskyMessage(
          id: message.id, conversationID: message.conversationID, role: message.role,
          text: partial.text, createdAt: message.createdAt, requestID: partial.requestID,
          sequence: message.sequence),
        revision: partial.revision)
    }.sorted {
      if $0.message.sequence != $1.message.sequence {
        return $0.message.sequence < $1.message.sequence
      }
      return $0.message.id < $1.message.id
    }
    _ = try HuskyMessageBodyValidator.seed(
      snapshots, conversationID: conversationID, afterSequence: afterSequence,
      maximumBytes: self.capabilities?.maximumMessageUTF8Bytes ?? UInt32.max)
    return snapshots
  }

  private func stopAfterUnseededPartialMessage(
    session: any HuskyConversationSession, conversationID: String, generation: UInt64
  ) async {
    guard self.generation == generation,
      self.selectedConversationID == conversationID
    else { return }
    self.isConnected = false
    self.statusText =
      "The backend resumed an in-progress reply without its exact state. Automatic recovery is paused to avoid corrupting it."
    self.session = nil
    await self.finishSession(session)
  }

  private static func isMissingPartialMessageBaseline(_ error: Error) -> Bool {
    guard let recoveryError = error as? HuskyPartialRecoveryError,
      case .missingBaseline = recoveryError
    else { return false }
    return true
  }

  private static func isUnsupportedPartialRecoveryAdapter(_ error: Error) -> Bool {
    guard let recoveryError = error as? HuskyPartialRecoveryError,
      case .unsupportedAdapter = recoveryError
    else { return false }
    return true
  }

  private func mergeOlderPage(_ incoming: [HuskyMessage]) {
    var byID = Dictionary(uniqueKeysWithValues: self.messages.map { ($0.id, $0) })
    for message in incoming {
      guard let existing = byID[message.id] else {
        byID[message.id] = message
        continue
      }
      // Existing rows may include stream deltas newer than the page snapshot.
      // On equal sequence keep the in-memory value, which may be more current.
      if message.sequence < existing.sequence { continue }
      if message.sequence == existing.sequence { continue }
      byID[message.id] = message
    }
    self.messages = byID.values.sorted(by: Self.messageOrder)
  }

  private func upsertEventMessage(_ message: HuskyMessage) {
    guard let index = self.messages.firstIndex(where: { $0.id == message.id }) else {
      self.messages.append(message)
      return
    }
    if self.messages[index].sequence <= message.sequence {
      self.messages[index] = message
    }
  }

  private func upsertConversation(_ conversation: HuskyConversation, preferIncoming: Bool) {
    if let index = self.conversations.firstIndex(where: { $0.id == conversation.id }) {
      if preferIncoming || conversation.updatedAt >= self.conversations[index].updatedAt {
        self.conversations[index] = conversation
      }
    } else if preferIncoming {
      self.conversations.insert(conversation, at: 0)
    } else {
      self.conversations.append(conversation)
    }
  }

  private func finishRequest(_ requestID: String?, conversationID: String) {
    guard let requestID, let profileID = self.profileID else { return }
    let key = RequestKey(profileID: profileID, conversationID: conversationID, requestID: requestID)
    if self.acceptedRequests.contains(key) {
      self.completedRequests.insert(key)
    } else {
      self.requestPayloads.removeValue(forKey: key)
    }
    self.inFlightSubmissions.remove(key)
  }

  private func waitForAcceptance(_ key: RequestKey, generation: UInt64) async
    -> HuskySubmissionResult
  {
    if self.acceptedRequests.contains(key) { return .accepted }
    if self.failedBeforeAcceptance.contains(key) { return .rejected }
    let waiterID = UUID()
    return await withCheckedContinuation { continuation in
      var waiter = AcceptanceWaiter(key: key, continuation: continuation, timeoutTask: nil)
      waiter.timeoutTask = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: self?.acceptanceTimeout ?? .seconds(12)) } catch { return }
        guard let self,
          self.generation == generation,
          self.acceptanceWaiters[waiterID] != nil
        else { return }
        self.resolveWaiter(waiterID, result: .unconfirmed)
      }
      self.acceptanceWaiters[waiterID] = waiter
    }
  }

  private func resolveWaiters(for key: RequestKey, result: HuskySubmissionResult) {
    for id in self.acceptanceWaiters.compactMap({ $0.value.key == key ? $0.key : nil }) {
      self.resolveWaiter(id, result: result)
    }
  }

  private func resolveWaiter(_ id: UUID, result: HuskySubmissionResult) {
    guard let waiter = self.acceptanceWaiters.removeValue(forKey: id) else { return }
    waiter.timeoutTask?.cancel()
    waiter.continuation.resume(returning: result)
  }

  private func resolveAllWaiters(_ result: HuskySubmissionResult) {
    for id in Array(self.acceptanceWaiters.keys) {
      self.resolveWaiter(id, result: result)
    }
  }

  private func clearRequestState() {
    self.requestPayloads = [:]
    self.acceptedRequests = []
    self.completedRequests = []
    self.failedBeforeAcceptance = []
    self.inFlightSubmissions = []
  }

  private func finishSession(_ session: (any HuskyConversationSession)?) async {
    guard let session else { return }
    do {
      _ = try await self.bounded(self.cleanupTimeout) {
        await session.end()
        return true
      }
    } catch {
      // Cleanup is best-effort and bounded. The generation has already moved
      // on, so a late teardown cannot change the active UI state.
    }
  }

  private func bounded<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let pair = AsyncThrowingStream<T, any Error>.makeStream(
      of: T.self, bufferingPolicy: .bufferingOldest(1))
    let operationTask = Task {
      do {
        let value = try await operation()
        pair.continuation.yield(value)
        pair.continuation.finish()
      } catch {
        pair.continuation.finish(throwing: error)
      }
    }
    let timeoutTask = Task {
      do { try await Task.sleep(for: timeout) } catch { return }
      pair.continuation.finish(throwing: TimeoutError.elapsed)
    }
    defer {
      operationTask.cancel()
      timeoutTask.cancel()
    }
    for try await value in pair.stream { return value }
    throw TimeoutError.elapsed
  }

  private static func pageSize(preferred: UInt32, maximum: UInt32) -> UInt32 {
    max(1, min(preferred == 0 ? 50 : preferred, maximum == 0 ? 50 : maximum))
  }

  private static func uniqueConversations(_ input: [HuskyConversation]) -> [HuskyConversation] {
    var seen = Set<String>()
    return input.filter { seen.insert($0.id).inserted }
  }

  private static func uniqueMessages(_ input: [HuskyMessage]) -> [HuskyMessage] {
    var byID: [String: HuskyMessage] = [:]
    for message in input {
      if byID[message.id].map({ $0.sequence <= message.sequence }) ?? true {
        byID[message.id] = message
      }
    }
    return byID.values.sorted(by: Self.messageOrder)
  }

  private static func messageOrder(_ lhs: HuskyMessage, _ rhs: HuskyMessage) -> Bool {
    if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
    return lhs.id < rhs.id
  }

  private static func statusLabel(_ status: HuskyBackendStatus) -> String {
    switch status {
    case .thinking: "Thinking…"
    case .typing: "Typing…"
    case .waiting: "Waiting…"
    case .idle: ""
    case .error: "The backend reported an error."
    case .unknown: "The backend is working…"
    }
  }

  private static func safeMessage(for error: any Error, operation: String) -> String {
    if let clientError = error as? HuskyClientError {
      switch clientError {
      case .invalidPageSize, .messageTooLarge:
        return "The backend rejected the request limits."
      case .unsupportedProtocolVersion, .incompatibleClientVersion:
        return "This backend does not support the required Husky protocol."
      case .eventBufferOverflow, .resynchronizationRequired:
        return "The event stream needs to reconnect."
      default:
        return "The backend returned an invalid response."
      }
    }
    return "Could not \(operation). Check the connection and try again."
  }
}
