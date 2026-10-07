import GRPCCore
import GRPCInProcessTransport
import GRPCProtobuf
import HuskyCore
import HuskyFixture
import HuskyProtocol
import XCTest

final class HuskyPartialRecoveryTransportTests: XCTestCase, @unchecked Sendable {
  func testFixtureSnapshotSeedsMidMessageReplay() async throws {
    let transport = InProcessTransport()
    let service = HuskyFixtureService(
      store: HuskyFixtureStore(configuration: .init(responseStepDelay: .milliseconds(250))))
    let server = GRPCServer(transport: transport.server, services: [service])
    let serverTask = Task { try await server.serve() }
    defer { serverTask.cancel() }

    try await withGRPCClient(transport: transport.client) { client in
      let backend = HuskyHuskyBackend.Client(wrapping: client)
      let api = GRPCHuskyChatClient(backend: backend)
      let capabilities = try await api.getCapabilities()
      XCTAssertTrue(capabilities.features.contains("partial_message_snapshots"))

      let conversation = try await api.createConversation(
        requestID: "partial-recovery-create", title: "Partial recovery")
      let initial = try await api.getHistory(
        conversationID: conversation.id, pageSize: 100, before: nil)
      XCTAssertTrue(initial.partialMessages.isEmpty)

      let firstSession = try await api.openConversation(
        conversationID: conversation.id, afterSequence: initial.snapshotSequence,
        resumeToken: nil, partialMessages: initial.partialMessages)
      let firstRecorder = PartialRecoveryRecorder()
      let firstTask = Task {
        for try await event in firstSession.events { await firstRecorder.append(event) }
      }
      try await firstSession.submit(requestID: "completed-before-recovery", text: "previous")
      _ = try await waitForEvent(in: firstRecorder) { event in
        if case .messageCompleted(let requestID, _) = event.event {
          return requestID == "completed-before-recovery"
        }
        return false
      }
      try await firstSession.submit(requestID: "partial-recovery-request", text: "seed this")

      let firstDelta = try await waitForEvent(in: firstRecorder) { event in
        if case .textDelta(let requestID, _, let revision, _, _) = event.event {
          return requestID == "partial-recovery-request" && revision == 1
        }
        return false
      }
      let snapshot = try await api.getHistory(
        conversationID: conversation.id, pageSize: 1, before: nil)
      XCTAssertTrue(snapshot.hasMore)
      let olderCursor = try XCTUnwrap(snapshot.nextCursor)
      let seed = try XCTUnwrap(snapshot.partialMessages.first)
      XCTAssertEqual(seed.message.sequence, firstDelta.sequence - 1)
      XCTAssertEqual(seed.revision, 1)
      XCTAssertEqual(seed.message.text, "Fixture response")
      XCTAssertLessThanOrEqual(seed.message.sequence, snapshot.snapshotSequence)
      await firstSession.end()
      try await firstTask.value

      let resumed = try await api.openConversation(
        conversationID: conversation.id, afterSequence: snapshot.snapshotSequence,
        resumeToken: nil, partialMessages: snapshot.partialMessages)
      let resumedRecorder = PartialRecoveryRecorder()
      let resumedTask = Task {
        for try await event in resumed.events { await resumedRecorder.append(event) }
      }
      let secondDelta = try await waitForEvent(in: resumedRecorder) { event in
        if case .textDelta(_, _, let revision, _, _) = event.event { return revision == 2 }
        return false
      }
      XCTAssertGreaterThan(secondDelta.sequence, snapshot.snapshotSequence)
      let completed = try await waitForEvent(in: resumedRecorder) { event in
        if case .messageCompleted = event.event { return true }
        return false
      }
      guard case .messageCompleted(_, let finalMessage) = completed.event else {
        return XCTFail("the resumed stream should deliver canonical completion")
      }
      XCTAssertEqual(finalMessage.text, "Fixture response: seed this")
      await resumed.end()
      try await resumedTask.value

      let olderPage = try await api.getHistory(
        conversationID: conversation.id, pageSize: 1, before: olderCursor)
      XCTAssertEqual(olderPage.snapshotSequence, snapshot.snapshotSequence)
      XCTAssertEqual(olderPage.partialMessages, snapshot.partialMessages)
      let completedHistory = try await api.getHistory(
        conversationID: conversation.id, pageSize: 100, before: nil)
      XCTAssertTrue(completedHistory.partialMessages.isEmpty)
    }
  }

  func testSeededTransportValidatesRevisionAndCumulativeUTF8Bytes() async throws {
    try await withScriptedService(maximumBytes: 32) { api, conversationID in
      let snapshot = try await api.getHistory(
        conversationID: conversationID, pageSize: 10, before: nil)
      let baseline = try XCTUnwrap(snapshot.partialMessages.first)
      XCTAssertEqual(baseline.message.text, "old")
      let events = try await collect(
        from: api,
        conversationID: conversationID,
        seed: baseline
      )
      XCTAssertEqual(events.count, 3)
      guard case .textDelta(_, _, 2, "é", nil) = events[0].event,
        case .messageCompleted(_, let finalMessage) = events[1].event
      else {
        return XCTFail("replay should apply the next delta and canonical completion")
      }
      XCTAssertEqual(finalMessage.text, "canonical")
      XCTAssertEqual(events[1].sequence, 3)
    }

    try await withScriptedService(maximumBytes: 32) { api, conversationID in
      await self.assertStreamRejects(
        from: api, conversationID: conversationID, seed: nil,
        failure: .missingBaseline)
    }

    try await withScriptedService(maximumBytes: 32) { api, conversationID in
      await self.assertStreamRejects(
        from: api, conversationID: conversationID,
        seed: self.seed(text: "old", revision: 2),
        failure: .revision)
    }

    try await withScriptedService(maximumBytes: 4, snapshotText: "éé") { api, conversationID in
      await self.assertStreamRejects(
        from: api, conversationID: conversationID,
        seed: self.seed(text: "éé", revision: 1),
        failure: .cumulativeByteLimit)
    }
  }

  private func withScriptedService(
    maximumBytes: UInt32,
    snapshotText: String = "old",
    operation: (GRPCHuskyChatClient<InProcessTransport.Client>, String) async throws -> Void
  ) async throws {
    let transport = InProcessTransport()
    let service = PartialRecoveryScriptedService(
      maximumBytes: maximumBytes, snapshotText: snapshotText)
    let server = GRPCServer(transport: transport.server, services: [service])
    let serverTask = Task { try await server.serve() }
    defer { serverTask.cancel() }
    try await withGRPCClient(transport: transport.client) { client in
      let api = GRPCHuskyChatClient(backend: HuskyHuskyBackend.Client(wrapping: client))
      try await operation(api, PartialRecoveryScriptedService.conversationID)
    }
  }

  private func collect(
    from api: GRPCHuskyChatClient<InProcessTransport.Client>,
    conversationID: String,
    seed: HuskyPartialMessageSnapshot?
  ) async throws -> [HuskySequencedEvent] {
    let session = try await api.openConversation(
      conversationID: conversationID, afterSequence: 1, resumeToken: nil,
      partialMessages: seed.map { [$0] } ?? [])
    defer { Task { await session.end() } }
    var events: [HuskySequencedEvent] = []
    for try await event in session.events { events.append(event) }
    return events
  }

  private func assertStreamRejects(
    from api: GRPCHuskyChatClient<InProcessTransport.Client>,
    conversationID: String,
    seed: HuskyPartialMessageSnapshot?,
    failure: ExpectedStreamFailure
  ) async {
    do {
      _ = try await collect(from: api, conversationID: conversationID, seed: seed)
      XCTFail("the malformed replay should be rejected")
    } catch let error as HuskyPartialRecoveryError {
      guard failure == .missingBaseline else {
        return XCTFail("unexpected partial-recovery error: \(error)")
      }
      XCTAssertEqual(error, .missingBaseline)
    } catch let error as HuskyClientError {
      switch (failure, error) {
      case (.revision, .malformedResponse("text delta revisions must increase")):
        break
      case (.cumulativeByteLimit, .messageTooLarge(actualUTF8Bytes: 6, maximum: 4)):
        break
      default:
        XCTFail("unexpected client error: \(error)")
      }
    } catch {
      XCTFail("unexpected stream error: \(error)")
    }
  }

  private enum ExpectedStreamFailure: Equatable {
    case missingBaseline
    case revision
    case cumulativeByteLimit
  }

  private func seed(text: String, revision: UInt64) -> HuskyPartialMessageSnapshot {
    HuskyPartialMessageSnapshot(
      message: HuskyMessage(
        id: PartialRecoveryScriptedService.messageID,
        conversationID: PartialRecoveryScriptedService.conversationID,
        role: .assistant,
        text: text,
        createdAt: .distantPast,
        requestID: PartialRecoveryScriptedService.requestID,
        sequence: 1
      ),
      revision: revision
    )
  }

  private func waitForEvent(
    in recorder: PartialRecoveryRecorder,
    matching predicate: @Sendable (HuskySequencedEvent) -> Bool
  ) async throws -> HuskySequencedEvent {
    for _ in 0..<300 {
      if let event = await recorder.snapshot().first(where: predicate) { return event }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw RPCError(
      code: .deadlineExceeded, message: "Timed out waiting for partial recovery event.")
  }
}

private actor PartialRecoveryRecorder {
  private var events: [HuskySequencedEvent] = []

  func append(_ event: HuskySequencedEvent) { events.append(event) }
  func snapshot() -> [HuskySequencedEvent] { events }
}

private struct PartialRecoveryScriptedService: HuskyHuskyBackend.SimpleServiceProtocol {
  static let conversationID = "partial-recovery-conversation"
  static let messageID = "partial-recovery-message"
  static let requestID = "partial-recovery-request"

  let maximumBytes: UInt32
  let snapshotText: String

  func getCapabilities(
    request: HuskyGetCapabilitiesRequest, context: ServerContext
  ) async throws -> HuskyGetCapabilitiesResponse {
    .with {
      $0.protocolVersion = "husky.v1"
      $0.minimumClientMajor = 1
      $0.maximumClientMajor = 1
      $0.maximumMessageUtf8Bytes = maximumBytes
      $0.defaultHistoryPageSize = 50
      $0.maximumHistoryPageSize = 100
      $0.features = ["partial_message_snapshots"]
    }
  }

  func listConversations(
    request: HuskyListConversationsRequest, context: ServerContext
  ) async throws -> HuskyListConversationsResponse { .init() }

  func createConversation(
    request: HuskyCreateConversationRequest, context: ServerContext
  ) async throws -> HuskyCreateConversationResponse { .init() }

  func getHistory(
    request: HuskyGetHistoryRequest, context: ServerContext
  ) async throws -> HuskyGetHistoryResponse {
    .with {
      $0.snapshotSequence = 1
      $0.partialMessages = [
        .with {
          $0.message = .with {
            $0.messageID = Self.messageID
            $0.conversationID = Self.conversationID
            $0.role = .assistant
            $0.text = snapshotText
            $0.requestID = Self.requestID
            $0.sequence = 1
          }
          $0.revision = 1
        }
      ]
    }
  }

  func conversationSession(
    request: RPCAsyncSequence<HuskyClientCommand, any Error>,
    response: RPCWriter<HuskyBackendEvent>,
    context: ServerContext
  ) async throws {
    var iterator = request.makeAsyncIterator()
    guard let command = try await iterator.next(),
      case .startSession(let start) = command.command,
      start.conversationID == Self.conversationID,
      start.afterSequence == 1
    else {
      throw RPCError(code: .invalidArgument, message: "Unexpected scripted session start.")
    }

    var delta = HuskyBackendEvent()
    delta.sequence = 2
    delta.textDelta = .with {
      $0.requestID = Self.requestID
      $0.messageID = Self.messageID
      $0.revision = 2
      $0.appendText = "é"
    }
    try await response.write(delta)

    var completion = HuskyBackendEvent()
    completion.sequence = 3
    completion.messageCompleted = .with {
      $0.requestID = Self.requestID
      $0.message = .with {
        $0.messageID = Self.messageID
        $0.conversationID = Self.conversationID
        $0.role = .assistant
        $0.text = "canonical"
        $0.requestID = Self.requestID
        $0.sequence = 3
      }
    }
    try await response.write(completion)

    var ready = HuskyBackendEvent()
    ready.sessionReady = .with {
      $0.conversationID = Self.conversationID
      $0.caughtUpThroughSequence = 3
      $0.resumeToken = "partial-recovery-token"
    }
    try await response.write(ready)
  }
}
