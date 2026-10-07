import Foundation
import XCTest

@testable import HuskyCore

final class HuskyConversationControllerTests: XCTestCase {
  @MainActor
  func testAttachDoesNotCreateAConversationForAnEmptyBackend() async {
    let client = ControlledChatClient(
      conversations: .init(conversations: [], nextCursor: nil, hasMore: false))
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))

    await controller.attach(profileID: UUID(), client: client)

    XCTAssertTrue(controller.conversations.isEmpty)
    XCTAssertNil(controller.selectedConversationID)
    XCTAssertEqual(controller.statusText, "Connected. Create a conversation to begin.")
    let createdCount = await client.createCount()
    XCTAssertEqual(createdCount, 0)
  }

  @MainActor
  func testPreferredConversationIsResolvedOutsideFirstListPage() async {
    let first = Self.conversation("c-1")
    let preferred = Self.conversation("c-2")
    let session = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(conversations: [first], nextCursor: "page-2", hasMore: true),
      histories: [
        "c-2|": [.init(messages: [], nextCursor: nil, hasMore: false, snapshotSequence: 3)]
      ],
      sessions: [session])
    await client.setConversationPage(
      .init(conversations: [preferred], nextCursor: nil, hasMore: false), before: "page-2")
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))

    await controller.attach(profileID: UUID(), client: client, preferredConversationID: "c-2")

    XCTAssertEqual(controller.selectedConversationID, "c-2")
    XCTAssertEqual(Set(controller.conversations.map(\.id)), Set(["c-1", "c-2"]))
    let opens = await client.openRequests()
    XCTAssertEqual(opens.first?.conversationID, "c-2")
    XCTAssertEqual(opens.first?.afterSequence, 3)
  }

  @MainActor
  func testOlderPageDoesNotOverwriteAnExistingNewerMessage() async {
    let conversation = Self.conversation("c-1")
    let client = ControlledChatClient(
      conversations: .init(conversations: [conversation], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [
          .init(
            messages: [Self.message("m-1", "streamed", sequence: 8)], nextCursor: "older",
            hasMore: true, snapshotSequence: 8)
        ],
        "c-1|older": [
          .init(
            messages: [
              Self.message("m-0", "older", sequence: 2),
              Self.message("m-1", "stale page copy", sequence: 4),
            ], nextCursor: nil, hasMore: false, snapshotSequence: 8)
        ],
      ],
      sessions: [ControlledSession()])
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    await controller.loadOlderMessages()

    XCTAssertEqual(controller.messages.map(\.id), ["m-0", "m-1"])
    XCTAssertEqual(controller.messages.first(where: { $0.id == "m-1" })?.text, "streamed")
    XCTAssertFalse(controller.hasMoreHistory)
  }

  @MainActor
  func testSequenceGapRefreshesCanonicalHistoryBeforeReopeningStream() async {
    let conversation = Self.conversation("c-1")
    let first = ControlledSession()
    let second = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(conversations: [conversation], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [
          .init(
            messages: [Self.message("m-1", "before gap", sequence: 1)], nextCursor: nil,
            hasMore: false, snapshotSequence: 1),
          .init(
            messages: [Self.message("m-2", "canonical", sequence: 2)], nextCursor: nil,
            hasMore: false, snapshotSequence: 2),
        ]
      ],
      sessions: [first, second])
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)
    first.emit(
      .init(
        sequence: 0,
        event: .sessionReady(conversationID: "c-1", caughtUpThrough: 1, resumeToken: "resume-1")))
    await self.waitUntil { controller.isConnected }

    first.emit(
      .init(sequence: 3, event: .statusChanged(requestID: nil, status: .typing, detail: "")))
    await self.waitUntil { await client.openRequests().count == 2 }

    // The refresh is a paginated snapshot. It updates the current page while
    // retaining already loaded older rows that are outside this page.
    XCTAssertEqual(controller.messages.map(\.id), ["m-1", "m-2"])
    XCTAssertEqual(controller.messages.last?.text, "canonical")
    let opens = await client.openRequests()
    XCTAssertEqual(opens.last?.afterSequence, 2)
    XCTAssertNil(opens.last?.resumeToken)
  }

  @MainActor
  func testSubmitReturnsOnlyAfterMatchingAcceptanceAndRetainsStablePayload() async {
    let conversation = Self.conversation("c-1")
    let session = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(conversations: [conversation], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [.init(messages: [], nextCursor: nil, hasMore: false, snapshotSequence: 0)]
      ],
      sessions: [session])
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(100),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    let firstAttempt = Task { @MainActor in
      await controller.submitResult(text: "hello", requestID: "req-1")
    }
    await self.waitUntil { await session.submissions().count == 1 }
    let timedOut = await firstAttempt.value
    XCTAssertEqual(timedOut, .unconfirmed)

    let changedPayload = await controller.submitResult(text: "different", requestID: "req-1")
    XCTAssertEqual(changedPayload, .unconfirmed)
    let submissionCount = await session.submissions().count
    XCTAssertEqual(submissionCount, 1)

    let retry = Task { @MainActor in
      await controller.submitResult(text: "hello", requestID: "req-1")
    }
    await self.waitUntil { await session.submissions().count == 2 }
    session.emit(
      .init(
        sequence: 0,
        event: .messageAccepted(
          requestID: "req-1", userMessage: Self.message("m-user", "hello", sequence: 1),
          replayed: true)))

    let retryResult = await retry.value
    XCTAssertEqual(retryResult, .accepted)
    XCTAssertNil(controller.activeRequestID)

    let completedResponse = HuskyMessage(
      id: "m-response", conversationID: "c-1", role: .assistant, text: "done",
      createdAt: Date(timeIntervalSince1970: 2), requestID: "req-1", sequence: 1)
    session.emit(
      .init(
        sequence: 1,
        event: .messageCompleted(requestID: "req-1", message: completedResponse)))
    await self.waitUntil { controller.messages.contains(where: { $0.id == "m-response" }) }

    let changedCompletedPayload = await controller.submitResult(
      text: "changed after completion", requestID: "req-1")
    XCTAssertEqual(changedCompletedPayload, .rejected)
    let completedSubmissions = await session.submissions().count
    XCTAssertEqual(completedSubmissions, 2)
  }

  @MainActor
  func testReplayedAcceptanceDoesNotBlockANewSubmission() async {
    let session = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(
        conversations: [Self.conversation("c-1")], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [
          .init(
            messages: [Self.message("m-completed", "finished", sequence: 1)], nextCursor: nil,
            hasMore: false, snapshotSequence: 1)
        ]
      ],
      sessions: [session])
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .seconds(1),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    session.emit(
      .init(
        sequence: 0,
        event: .messageAccepted(
          requestID: "req-completed",
          userMessage: Self.message("m-completed", "finished", sequence: 1),
          replayed: true)))
    await self.waitUntil { controller.messages.contains(where: { $0.id == "m-completed" }) }
    XCTAssertNil(controller.activeRequestID)

    let submission = Task { @MainActor in
      await controller.submitResult(text: "next", requestID: "req-next")
    }
    await self.waitUntil { await session.submissions().count == 1 }
    session.emit(
      .init(
        sequence: 2,
        event: .messageAccepted(
          requestID: "req-next", userMessage: Self.message("m-next", "next", sequence: 2),
          replayed: false)))

    let result = await submission.value
    XCTAssertEqual(result, .accepted)
    XCTAssertEqual(controller.activeRequestID, "req-next")
  }

  @MainActor
  func testOlderPageFromBeforeResyncCannotOverwriteFreshSnapshot() async {
    let firstSession = ControlledSession()
    let secondSession = ControlledSession()
    let pageGate = HistoryPageGate()
    let client = ControlledChatClient(
      conversations: .init(
        conversations: [Self.conversation("c-1")], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [
          .init(
            messages: [Self.message("m-1", "old snapshot", sequence: 2)], nextCursor: "older",
            hasMore: true, snapshotSequence: 2),
          .init(
            messages: [Self.message("m-2", "fresh snapshot", sequence: 3)], nextCursor: nil,
            hasMore: false, snapshotSequence: 3),
        ]
      ],
      sessions: [firstSession, secondSession], olderHistoryGate: pageGate)
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    let olderLoad = Task { @MainActor in await controller.loadOlderMessages() }
    await self.waitUntil { await pageGate.hasPendingRequest() }
    firstSession.emit(
      .init(
        sequence: 0,
        event: .sessionReady(conversationID: "c-1", caughtUpThrough: 2, resumeToken: nil)))
    await self.waitUntil { controller.isConnected }
    firstSession.emit(
      .init(
        sequence: 4, event: .statusChanged(requestID: nil, status: .typing, detail: "gap")))
    await self.waitUntil { await client.openRequests().count == 2 }
    await pageGate.release(
      .init(
        messages: [Self.message("m-0", "stale older page", sequence: 1)], nextCursor: "older-2",
        hasMore: true, snapshotSequence: 2))
    await olderLoad.value

    XCTAssertEqual(controller.messages.map(\.id), ["m-1", "m-2"])
    XCTAssertEqual(controller.messages.last?.text, "fresh snapshot")
    XCTAssertFalse(controller.hasMoreHistory)
  }

  @MainActor
  func testReconnectResetsHistoryLoadingWhileOldPageIsPending() async {
    let firstSession = ControlledSession()
    let secondSession = ControlledSession()
    let pageGate = HistoryPageGate()
    let client = ControlledChatClient(
      conversations: .init(
        conversations: [Self.conversation("c-1")], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [
          .init(
            messages: [Self.message("m-1", "message", sequence: 1)], nextCursor: "older",
            hasMore: true, snapshotSequence: 1)
        ]
      ],
      sessions: [firstSession, secondSession], olderHistoryGate: pageGate)
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    let olderLoad = Task { @MainActor in await controller.loadOlderMessages() }
    await self.waitUntil { await pageGate.hasPendingRequest() }
    XCTAssertTrue(controller.isLoadingHistory)

    await controller.reconnect()

    XCTAssertFalse(controller.isLoadingHistory)
    await pageGate.release(
      .init(
        messages: [Self.message("m-0", "old page", sequence: 1)], nextCursor: nil,
        hasMore: false, snapshotSequence: 1))
    await olderLoad.value
    XCTAssertFalse(controller.isLoadingHistory)
  }

  @MainActor
  func testAmbiguousConversationCreateRetryReusesRequestIDAndTitle() async {
    let firstSession = ControlledSession()
    let secondSession = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(
        conversations: [Self.conversation("c-1")], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [.init(messages: [], nextCursor: nil, hasMore: false, snapshotSequence: 0)]
      ],
      sessions: [firstSession, secondSession])
    await client.failNextCreate()
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    await controller.createConversation(title: "A stable title")
    let firstCreate = await client.createRequests()
    XCTAssertEqual(firstCreate.count, 1)

    await controller.createConversation(title: "A changed title")
    let afterChangedTitle = await client.createRequests()
    XCTAssertEqual(afterChangedTitle.count, 1)

    await controller.createConversation(title: "A stable title")
    let retries = await client.createRequests()
    XCTAssertEqual(retries.count, 2)
    XCTAssertEqual(retries[0].requestID, retries[1].requestID)
    XCTAssertEqual(retries[0].title, retries[1].title)
  }

  @MainActor
  func testExplicitBackendFailureBeforeAcceptanceIsRejected() async {
    let session = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(
        conversations: [Self.conversation("c-1")], nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [.init(messages: [], nextCursor: nil, hasMore: false, snapshotSequence: 0)]
      ],
      sessions: [session])
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .seconds(1),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)

    let submission = Task { @MainActor in
      await controller.submitResult(text: "hello", requestID: "req-rejected")
    }
    await self.waitUntil { await session.submissions().count == 1 }
    session.emit(
      .init(
        sequence: 1,
        event: .requestFailed(
          requestID: "req-rejected", publicCode: "invalid_request", message: "Rejected",
          retryable: false)))

    let result = await submission.value
    XCTAssertEqual(result, .rejected)
    XCTAssertNil(controller.activeRequestID)
  }

  @MainActor
  func testLateEventFromPreviousConversationCannotMutateSelection() async {
    let first = ControlledSession()
    let second = ControlledSession()
    let client = ControlledChatClient(
      conversations: .init(
        conversations: [Self.conversation("c-1"), Self.conversation("c-2")],
        nextCursor: nil, hasMore: false),
      histories: [
        "c-1|": [.init(messages: [], nextCursor: nil, hasMore: false, snapshotSequence: 0)],
        "c-2|": [
          .init(
            messages: [Self.message("m-new", "second", sequence: 1)], nextCursor: nil,
            hasMore: false, snapshotSequence: 1)
        ],
      ],
      sessions: [first, second])
    let controller = HuskyConversationController(
      operationTimeout: .seconds(1), acceptanceTimeout: .milliseconds(80),
      cleanupTimeout: .milliseconds(30))
    await controller.attach(profileID: UUID(), client: client)
    await controller.selectConversation(id: "c-2")
    await self.waitUntil {
      controller.selectedConversationID == "c-2" && controller.messages.count == 1
    }

    first.emit(
      .init(
        sequence: 1,
        event: .messageStarted(
          requestID: "old", message: Self.message("m-old", "late", sequence: 1))))
    try? await Task.sleep(for: .milliseconds(30))

    XCTAssertEqual(controller.selectedConversationID, "c-2")
    XCTAssertEqual(controller.messages.map(\.id), ["m-new"])
  }

  @MainActor
  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ predicate: @escaping @MainActor () async -> Bool
  ) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if await predicate() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Condition was not reached before timeout")
  }

  private static func conversation(_ id: String) -> HuskyConversation {
    HuskyConversation(
      id: id, title: id, createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0))
  }

  private static func message(_ id: String, _ text: String, sequence: UInt64) -> HuskyMessage {
    HuskyMessage(
      id: id, conversationID: "c-1", role: .user, text: text,
      createdAt: Date(timeIntervalSince1970: TimeInterval(sequence)), requestID: nil,
      sequence: sequence)
  }
}

private actor SubmissionRecorder {
  private var values: [(String, String)] = []
  func record(_ requestID: String, text: String) { self.values.append((requestID, text)) }
  func snapshot() -> [(String, String)] { self.values }
}

private actor HistoryPageGate {
  private var continuation: CheckedContinuation<HuskyHistoryPage, Never>?

  func nextPage() async -> HuskyHistoryPage {
    await withCheckedContinuation { self.continuation = $0 }
  }

  func hasPendingRequest() -> Bool { self.continuation != nil }

  func release(_ page: HuskyHistoryPage) {
    guard let continuation = self.continuation else { return }
    self.continuation = nil
    continuation.resume(returning: page)
  }
}

private final class ControlledSession: HuskyConversationSession, @unchecked Sendable {
  let events: AsyncThrowingStream<HuskySequencedEvent, any Error>
  private let continuation: AsyncThrowingStream<HuskySequencedEvent, any Error>.Continuation
  private let recorder = SubmissionRecorder()
  private let slowEnd: Bool

  init(slowEnd: Bool = false) {
    let pair = AsyncThrowingStream<HuskySequencedEvent, any Error>.makeStream()
    self.events = pair.stream
    self.continuation = pair.continuation
    self.slowEnd = slowEnd
  }

  func submit(requestID: String, text: String) async throws {
    await self.recorder.record(requestID, text: text)
  }

  func cancel(requestID: String) async throws {}

  func end() async {
    if self.slowEnd { try? await Task.sleep(for: .seconds(30)) }
    self.continuation.finish()
  }

  func emit(_ event: HuskySequencedEvent) {
    self.continuation.yield(event)
  }

  func submissions() async -> [(String, String)] { await self.recorder.snapshot() }
}

private actor ControlledChatClient: HuskyChatClient {
  private var conversationPages: [String: HuskyConversationPage]
  private var historyPages: [String: [HuskyHistoryPage]]
  private var sessions: [ControlledSession]
  private var opened: [(conversationID: String, afterSequence: UInt64, resumeToken: String?)] = []
  private var createdCount = 0
  private var createFailuresRemaining = 0
  private var creates: [(requestID: String, title: String)] = []
  private let olderHistoryGate: HistoryPageGate?

  init(
    conversations: HuskyConversationPage,
    histories: [String: [HuskyHistoryPage]] = [:],
    sessions: [ControlledSession] = [],
    olderHistoryGate: HistoryPageGate? = nil
  ) {
    self.conversationPages = ["": conversations]
    self.historyPages = histories
    self.sessions = sessions
    self.olderHistoryGate = olderHistoryGate
  }

  func setConversationPage(_ page: HuskyConversationPage, before: String?) {
    self.conversationPages[before ?? ""] = page
  }

  func getCapabilities() async throws -> HuskyCapabilities {
    HuskyCapabilities(
      protocolVersion: "husky.v1", minimumClientMajor: 1, maximumClientMajor: 1,
      maximumMessageUTF8Bytes: 64_000, defaultHistoryPageSize: 50,
      maximumHistoryPageSize: 100, features: [])
  }

  func listConversations(pageSize: UInt32, before cursor: String?) async throws
    -> HuskyConversationPage
  {
    self.conversationPages[cursor ?? ""]
      ?? .init(conversations: [], nextCursor: nil, hasMore: false)
  }

  func createConversation(requestID: String, title: String) async throws -> HuskyConversation {
    self.creates.append((requestID: requestID, title: title))
    if self.createFailuresRemaining > 0 {
      self.createFailuresRemaining -= 1
      throw HuskyClientError.resynchronizationRequired
    }
    self.createdCount += 1
    return HuskyConversation(
      id: "created-\(self.createdCount)", title: title,
      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
  }

  func getHistory(conversationID: String, pageSize: UInt32, before cursor: String?) async throws
    -> HuskyHistoryPage
  {
    if cursor == "older", let olderHistoryGate = self.olderHistoryGate {
      return await olderHistoryGate.nextPage()
    }
    let key = "\(conversationID)|\(cursor ?? "")"
    guard var pages = self.historyPages[key], !pages.isEmpty else {
      return .init(messages: [], nextCursor: nil, hasMore: false, snapshotSequence: 0)
    }
    let page = pages.removeFirst()
    self.historyPages[key] = pages
    return page
  }

  func openConversation(
    conversationID: String,
    afterSequence: UInt64,
    resumeToken: String?
  ) async throws -> any HuskyConversationSession {
    self.opened.append((conversationID, afterSequence, resumeToken))
    guard !self.sessions.isEmpty else { throw HuskyClientError.resynchronizationRequired }
    return self.sessions.removeFirst()
  }

  func openRequests() -> [(conversationID: String, afterSequence: UInt64, resumeToken: String?)] {
    self.opened
  }

  func createCount() -> Int { self.createdCount }

  func failNextCreate() { self.createFailuresRemaining += 1 }

  func createRequests() -> [(requestID: String, title: String)] { self.creates }
}
