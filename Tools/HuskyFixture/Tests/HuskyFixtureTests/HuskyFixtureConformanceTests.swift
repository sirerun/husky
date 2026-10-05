import GRPCCore
import GRPCInProcessTransport
import GRPCProtobuf
import HuskyCore
import HuskyFixture
import HuskyProtocol
import XCTest

final class HuskyFixtureConformanceTests: XCTestCase, @unchecked Sendable {
  func testCapabilitiesAndCursorPaginationUseFrozenLimitsAndStablePages() async throws {
    try await withFixture { backend in
      let capabilities = try await backend.getCapabilities(.init())
      XCTAssertEqual(capabilities.protocolVersion, "husky.v1")
      XCTAssertEqual(capabilities.defaultHistoryPageSize, 50)
      XCTAssertEqual(capabilities.maximumHistoryPageSize, 100)
      XCTAssertTrue(capabilities.features.contains("fixture"))

      var created: [String] = []
      for index in 1...3 {
        let response = try await backend.createConversation(
          .with {
            $0.clientRequestID = "create-\(index)"
            $0.title = "Conversation \(index)"
          })
        created.append(response.conversation.conversationID)
      }
      let duplicate = try await backend.createConversation(
        .with {
          $0.clientRequestID = "create-1"
          $0.title = "Conversation 1"
        })
      XCTAssertEqual(duplicate.conversation.conversationID, created[0])
      do {
        _ = try await backend.createConversation(
          .with {
            $0.clientRequestID = "create-1"
            $0.title = "Changed title"
          })
        XCTFail("reusing a create request ID with different content must fail")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }

      let first = try await backend.listConversations(.with { $0.pageSize = 2 })
      XCTAssertEqual(first.conversations.map(\.conversationID), Array(created.suffix(2)))
      XCTAssertTrue(first.hasMore_p)
      XCTAssertFalse(first.nextCursor.isEmpty)
      let second = try await backend.listConversations(
        .with {
          $0.pageSize = 2
          $0.beforeCursor = first.nextCursor
        })
      XCTAssertEqual(second.conversations.map(\.conversationID), [created[0]])
      XCTAssertFalse(second.hasMore_p)

      do {
        _ = try await backend.listConversations(.with { $0.pageSize = 101 })
        XCTFail("page_size above the frozen maximum must fail")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }
    }
  }

  func testHistoryUsesSnapshotCursorAndPagesAreOldestToNewest() async throws {
    try await withFixture { backend in
      let conversation = try await createConversation("history", using: backend)
      try await backend.conversationSession { writer in
        try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
        for index in 1...5 {
          try await writer.write(
            self.submit("history-\(index)", "message \(index)", conversationID: conversation))
        }
        try await self.waitForAssistantMessages(5, conversationID: conversation, using: backend)
        try await writer.write(.with { $0.endSession = .init() })
      } onResponse: { response in
        for try await _ in response.messages {}
      }

      let first = try await backend.getHistory(
        .with {
          $0.conversationID = conversation
          $0.pageSize = 3
        })
      XCTAssertEqual(first.messages.count, 3)
      XCTAssertTrue(first.hasMore_p)
      XCTAssertGreaterThan(first.snapshotSequence, 0)

      var pages = [first.messages]
      var current = first
      var consumedCursors = Set<String>()
      while current.hasMore_p, pages.count < 10 {
        let cursor = current.nextCursor
        guard !cursor.isEmpty else {
          XCTFail("has_more requires a next cursor")
          break
        }
        guard consumedCursors.insert(cursor).inserted else {
          XCTFail("history pagination must advance to a new cursor")
          break
        }

        current = try await backend.getHistory(
          .with {
            $0.conversationID = conversation
            $0.pageSize = 3
            $0.beforeCursor = cursor
          })
        XCTAssertEqual(current.snapshotSequence, first.snapshotSequence)
        XCTAssertLessThanOrEqual(current.messages.count, 3)
        pages.append(current.messages)
      }

      XCTAssertFalse(current.hasMore_p, "history pagination must terminate")
      XCTAssertTrue(current.nextCursor.isEmpty)
      XCTAssertEqual(pages.map(\.count), [3, 3, 3, 1])

      for page in pages {
        XCTAssertFalse(page.isEmpty)
        XCTAssertEqual(page.map(\.sequence), page.map(\.sequence).sorted())
      }
      for index in 0..<(pages.count - 1) {
        guard let newerPageFirst = pages[index].first, let olderPageLast = pages[index + 1].last
        else {
          XCTFail("each history page must contain messages")
          continue
        }
        XCTAssertGreaterThan(newerPageFirst.sequence, olderPageLast.sequence)
      }

      let newestToOldest = pages.flatMap { $0 }
      XCTAssertEqual(newestToOldest.count, 10)
      XCTAssertEqual(Set(newestToOldest.map(\.messageID)).count, 10)
      XCTAssertEqual(newestToOldest.filter { $0.role == .user }.count, 5)
      XCTAssertEqual(newestToOldest.filter { $0.role == .assistant }.count, 5)
      let oldestToNewest = pages.reversed().flatMap { $0 }
      XCTAssertEqual(oldestToNewest.map(\.sequence), oldestToNewest.map(\.sequence).sorted())
    }
  }

  func testDuplicateSubmissionReplaysOriginalAcceptanceWithoutDuplicateMessage() async throws {
    let recorder = EventRecorder()
    try await withFixture { backend in
      let conversation = try await createConversation("duplicate", using: backend)
      try await backend.conversationSession { writer in
        try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
        try await writer.write(
          self.submit("stable-id", "same payload", conversationID: conversation))
        try await writer.write(
          self.submit("stable-id", "same payload", conversationID: conversation))
        try await Task.sleep(for: .milliseconds(150))
        try await writer.write(.with { $0.cancelRequest.requestID = "stable-id" })
        try await writer.write(.with { $0.endSession = .init() })
      } onResponse: { response in
        for try await event in response.messages { await recorder.append(event) }
      }

      let accepted = await recorder.snapshot().compactMap { event -> HuskyMessageAccepted? in
        guard case .messageAccepted(let accepted) = event.event else { return nil }
        return accepted
      }
      XCTAssertEqual(accepted.count, 2)
      XCTAssertFalse(accepted[0].replayedIdempotentResult)
      XCTAssertTrue(accepted[1].replayedIdempotentResult)
      XCTAssertEqual(accepted[0].userMessage.messageID, accepted[1].userMessage.messageID)

      let history = try await backend.getHistory(
        .with {
          $0.conversationID = conversation
          $0.pageSize = 100
        })
      XCTAssertEqual(history.messages.filter { $0.role == .user }.count, 1)
      XCTAssertEqual(history.messages.filter { $0.role == .assistant }.count, 1)
    }
  }

  func testReusingRequestIDWithDifferentPayloadReturnsInvalidArgument() async throws {
    try await withFixture { backend in
      let conversation = try await createConversation("invalid-duplicate", using: backend)
      do {
        try await backend.conversationSession { writer in
          try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
          try await writer.write(
            self.submit("same-id", "first payload", conversationID: conversation))
          try await writer.write(
            self.submit("same-id", "changed payload", conversationID: conversation))
        } onResponse: { response in
          for try await _ in response.messages {}
        }
        XCTFail("reusing a request ID with a different payload must fail")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }

      let oversizedConversation = try await createConversation("oversized", using: backend)
      do {
        try await backend.conversationSession { writer in
          try await writer.write(
            self.start(conversationID: oversizedConversation, afterSequence: 0))
          try await writer.write(
            self.submit(
              "oversized-id", String(repeating: "é", count: 32_769),
              conversationID: oversizedConversation))
        } onResponse: { response in
          for try await _ in response.messages {}
        }
        XCTFail("the fixture must enforce the 64 KiB UTF-8 message limit")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }
    }
  }

  func testEmptyHistoryAndSessionConversationIDsReturnInvalidArgument() async throws {
    try await withFixture { backend in
      do {
        _ = try await backend.getHistory(.with { $0.pageSize = 1 })
        XCTFail("an empty conversation ID must be invalid")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }

      do {
        try await backend.conversationSession { writer in
          try await writer.write(self.start(conversationID: "", afterSequence: 0))
        } onResponse: { response in
          for try await _ in response.messages {}
        }
        XCTFail("an empty session conversation ID must be invalid")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }
    }
  }

  func testEmptyCancelRequestIDReturnsInvalidArgument() async throws {
    try await withFixture { backend in
      let conversation = try await createConversation("empty-cancel", using: backend)
      do {
        try await backend.conversationSession { writer in
          try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
          try await writer.write(.with { $0.cancelRequest.requestID = "" })
        } onResponse: { response in
          for try await _ in response.messages {}
        }
        XCTFail("an empty cancel request ID must be invalid")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .invalidArgument)
      }
    }
  }

  func testCancellationStopsScriptAndReconnectSignalsExpiredReplayWindow() async throws {
    let recorder = EventRecorder()
    try await withFixture(
      configuration: .init(retainedEventLimit: 2, responseStepDelay: .milliseconds(200))
    ) { backend in
      let conversation = try await createConversation("cancel", using: backend)
      try await backend.conversationSession { writer in
        try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
        for index in 1...3 {
          let requestID = "cancel-me-\(index)"
          try await writer.write(
            self.submit(requestID, "long scripted response", conversationID: conversation))
          try await writer.write(.with { $0.cancelRequest.requestID = requestID })
        }
        try await writer.write(.with { $0.endSession = .init() })
      } onResponse: { response in
        for try await event in response.messages { await recorder.append(event) }
      }

      let firstStream = await recorder.snapshot()
      XCTAssertTrue(
        firstStream.contains {
          if case .requestCancelled = $0.event { return true }
          return false
        })
      XCTAssertFalse(
        firstStream.contains {
          if case .messageCompleted = $0.event { return true }
          return false
        })
      let lastSequence = firstStream.map(\.sequence).max() ?? 0
      XCTAssertGreaterThan(lastSequence, 0)

      let resyncRecorder = EventRecorder()
      try await backend.conversationSession { writer in
        try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
      } onResponse: { response in
        for try await event in response.messages { await resyncRecorder.append(event) }
      }
      let resyncEvents = await resyncRecorder.snapshot()
      XCTAssertEqual(resyncEvents.count, 1)
      guard case .resyncRequired(let resync) = resyncEvents[0].event else {
        return XCTFail("an expired cursor must emit ResyncRequired")
      }
      XCTAssertEqual(resync.conversationID, conversation)
      XCTAssertGreaterThan(resync.oldestAvailableSequence, 1)
    }
  }

  func testCancellationAfterCompletionKeepsCoreConversationStreamOpen() async throws {
    try await withFixture { backend in
      let conversation = try await self.createConversation(
        "cancel-after-completion", using: backend)
      let client = GRPCHuskyChatClient(backend: backend)
      let session = try await client.openConversation(
        conversationID: conversation, afterSequence: 0, resumeToken: nil)
      let recorder = SequencedEventRecorder()
      let eventTask = Task {
        for try await event in session.events {
          await recorder.append(event)
        }
      }

      try await session.submit(requestID: "completed-request", text: "first question")
      try await self.waitForAssistantMessages(1, conversationID: conversation, using: backend)
      _ = try await self.waitForEvent(in: recorder) { event in
        if case .messageCompleted(let requestID, _) = event.event {
          return requestID == "completed-request"
        }
        return false
      }

      try await session.cancel(requestID: "completed-request")
      let acknowledgement = try await self.waitForEvent(in: recorder) { event in
        if case .requestCancelled(let requestID) = event.event {
          return requestID == "completed-request"
        }
        return false
      }
      XCTAssertEqual(acknowledgement.sequence, 0)

      try await session.submit(requestID: "next-request", text: "second question")
      _ = try await self.waitForEvent(in: recorder) { event in
        if case .messageCompleted(let requestID, _) = event.event {
          return requestID == "next-request"
        }
        return false
      }

      await session.end()
      do {
        try await eventTask.value
      } catch {
        XCTFail("the cancellation acknowledgement must not terminate the event stream: \(error)")
      }

      let history = try await backend.getHistory(
        .with {
          $0.conversationID = conversation
          $0.pageSize = 100
        })
      XCTAssertEqual(history.messages.filter { $0.role == .assistant }.count, 2)
    }
  }

  func testUnsolicitedServerMessageHasNoClientRequestIDAndReplaysAfterReconnect() async throws {
    let recorder = EventRecorder()
    try await withFixture(configuration: .init(emitUnsolicitedMessageOnFirstAttach: true)) {
      backend in
      let conversation = try await createConversation("unsolicited", using: backend)
      try await backend.conversationSession { writer in
        try await writer.write(self.start(conversationID: conversation, afterSequence: 0))
        try await Task.sleep(for: .milliseconds(100))
        try await writer.write(.with { $0.endSession = .init() })
      } onResponse: { response in
        for try await event in response.messages { await recorder.append(event) }
      }

      let initial = await recorder.snapshot()
      let serverMessage = try XCTUnwrap(
        initial.first { event in
          guard case .messageCompleted(let completed) = event.event else { return false }
          return completed.requestID.isEmpty
        })
      let watermark =
        initial.compactMap { event -> UInt64? in
          guard case .sessionReady(let ready) = event.event else { return nil }
          return ready.caughtUpThroughSequence
        }.first ?? 0
      XCTAssertGreaterThan(serverMessage.sequence, watermark)

      let reconnect = EventRecorder()
      try await backend.conversationSession { writer in
        try await writer.write(self.start(conversationID: conversation, afterSequence: watermark))
        try await writer.write(.with { $0.endSession = .init() })
      } onResponse: { response in
        for try await event in response.messages { await reconnect.append(event) }
      }
      let replay = await reconnect.snapshot()
      XCTAssertTrue(
        replay.contains { $0.sequence == serverMessage.sequence && $0 == serverMessage })
      XCTAssertTrue(
        replay.contains {
          if case .sessionReady = $0.event { return true }
          return false
        })
    }
  }

  private func withFixture(
    configuration: HuskyFixtureConfiguration = .init(),
    operation: (HuskyHuskyBackend.Client<InProcessTransport.Client>) async throws -> Void
  ) async throws {
    let transport = InProcessTransport()
    let service = HuskyFixtureService(store: HuskyFixtureStore(configuration: configuration))
    let server = GRPCServer(transport: transport.server, services: [service])
    let serverTask = Task { try await server.serve() }
    defer { serverTask.cancel() }

    try await withGRPCClient(transport: transport.client) { client in
      try await operation(HuskyHuskyBackend.Client(wrapping: client))
    }
  }

  private func createConversation(
    _ requestID: String,
    using backend: HuskyHuskyBackend.Client<InProcessTransport.Client>
  ) async throws -> String {
    let response = try await backend.createConversation(
      .with {
        $0.clientRequestID = requestID
        $0.title = "Fixture test"
      })
    return response.conversation.conversationID
  }

  private func waitForAssistantMessages(
    _ expectedCount: Int,
    conversationID: String,
    using backend: HuskyHuskyBackend.Client<InProcessTransport.Client>
  ) async throws {
    for _ in 0..<500 {
      let history = try await backend.getHistory(
        .with {
          $0.conversationID = conversationID
          $0.pageSize = 100
        })
      let assistantCount = history.messages.filter { $0.role == .assistant }.count
      if assistantCount == expectedCount { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw RPCError(
      code: .deadlineExceeded, message: "Fixture completion did not arrive within the test guard.")
  }

  private func waitForEvent(
    in recorder: SequencedEventRecorder,
    matching predicate: @Sendable (HuskySequencedEvent) -> Bool
  ) async throws -> HuskySequencedEvent {
    for _ in 0..<200 {
      if let event = await recorder.snapshot().first(where: predicate) { return event }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw RPCError(code: .deadlineExceeded, message: "The expected fixture event did not arrive.")
  }

  private func start(conversationID: String, afterSequence: UInt64) -> HuskyClientCommand {
    .with {
      $0.startSession = .with {
        $0.conversationID = conversationID
        $0.afterSequence = afterSequence
      }
    }
  }

  private func submit(_ requestID: String, _ text: String, conversationID: String)
    -> HuskyClientCommand
  {
    .with {
      $0.submitMessage = .with {
        $0.requestID = requestID
        $0.conversationID = conversationID
        $0.text = text
      }
    }
  }
}

private actor EventRecorder {
  private var events: [HuskyBackendEvent] = []
  func append(_ event: HuskyBackendEvent) { events.append(event) }
  func snapshot() -> [HuskyBackendEvent] { events }
}

private actor SequencedEventRecorder {
  private var events: [HuskySequencedEvent] = []

  func append(_ event: HuskySequencedEvent) { events.append(event) }
  func snapshot() -> [HuskySequencedEvent] { events }
}
