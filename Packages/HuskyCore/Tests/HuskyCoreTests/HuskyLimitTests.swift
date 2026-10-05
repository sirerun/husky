import HuskyProtocol
import XCTest

@testable import HuskyCore

final class HuskyLimitTests: XCTestCase {
  func testCapabilitiesRejectLimitsAboveFrozenCeilingsAndInvalidDefaults() throws {
    var capabilities = validCapabilities()
    XCTAssertEqual(try HuskyGRPCMapper.mapCapabilities(capabilities).maximumMessageUTF8Bytes, 4096)

    capabilities.maximumMessageUtf8Bytes = 65_537
    XCTAssertThrowsError(try HuskyGRPCMapper.mapCapabilities(capabilities))

    capabilities = validCapabilities()
    capabilities.maximumHistoryPageSize = 101
    XCTAssertThrowsError(try HuskyGRPCMapper.mapCapabilities(capabilities))

    capabilities = validCapabilities()
    capabilities.defaultHistoryPageSize = 51
    XCTAssertThrowsError(try HuskyGRPCMapper.mapCapabilities(capabilities))

    capabilities = validCapabilities()
    capabilities.maximumHistoryPageSize = 100
    capabilities.defaultHistoryPageSize = 51
    XCTAssertThrowsError(try HuskyGRPCMapper.mapCapabilities(capabilities))
  }

  func testCapabilitiesRejectZeroLimits() {
    var capabilities = validCapabilities()
    capabilities.maximumMessageUtf8Bytes = 0
    XCTAssertThrowsError(try HuskyGRPCMapper.mapCapabilities(capabilities))
    capabilities = validCapabilities()
    capabilities.defaultHistoryPageSize = 0
    XCTAssertThrowsError(try HuskyGRPCMapper.mapCapabilities(capabilities))
  }

  func testDeltaValidationChecksAggregateUTF8BytesAndIncreasingRevision() throws {
    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    let started = HuskyChatEvent.messageStarted(
      requestID: "r-1",
      message: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .assistant, text: "ab",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 1
      )
    )
    try HuskyMessageBodyValidator.apply(started, maximumBytes: 3, partialMessages: &partialMessages)

    let tooLarge = HuskyChatEvent.textDelta(
      requestID: "r-1", messageID: "m-1", revision: 1, append: "é", replace: nil
    )
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        tooLarge, maximumBytes: 3, partialMessages: &partialMessages)
    )

    let replacement = HuskyChatEvent.textDelta(
      requestID: "r-1", messageID: "m-1", revision: 2, append: "ignored", replace: "é"
    )
    try HuskyMessageBodyValidator.apply(
      replacement, maximumBytes: 3, partialMessages: &partialMessages)
    XCTAssertEqual(partialMessages["m-1"]?.text, "é")
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        replacement, maximumBytes: 3, partialMessages: &partialMessages)
    )
  }

  func testDeltaRequiresAStartedMessage() {
    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    let delta = HuskyChatEvent.textDelta(
      requestID: "r-1", messageID: "unknown-message", revision: 1, append: "hello", replace: nil
    )

    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        delta, maximumBytes: 4096, partialMessages: &partialMessages)
    ) { error in
      XCTAssertEqual(
        error as? HuskyClientError,
        .malformedResponse("text delta arrived before message start")
      )
    }
    XCTAssertTrue(partialMessages.isEmpty)
  }

  func testDeltaRequestIDMustMatchStartedMessage() throws {
    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    let started = HuskyChatEvent.messageStarted(
      requestID: "r-1",
      message: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .assistant, text: "start",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 1
      )
    )
    try HuskyMessageBodyValidator.apply(
      started, maximumBytes: 4096, partialMessages: &partialMessages)

    let mismatched = HuskyChatEvent.textDelta(
      requestID: "r-2", messageID: "m-1", revision: 1, append: "later", replace: nil
    )
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        mismatched, maximumBytes: 4096, partialMessages: &partialMessages)
    ) { error in
      XCTAssertEqual(
        error as? HuskyClientError,
        .malformedResponse("text delta request ID does not match message start")
      )
    }
    XCTAssertEqual(partialMessages["m-1"]?.text, "start")
    XCTAssertEqual(partialMessages["m-1"]?.revision, 0)
  }

  func testUnsolicitedMessageRequiresNilDeltaRequestID() throws {
    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    let started = HuskyChatEvent.messageStarted(
      requestID: nil,
      message: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .assistant, text: "start",
        createdAt: Date(timeIntervalSince1970: 0), requestID: nil, sequence: 1
      )
    )
    try HuskyMessageBodyValidator.apply(
      started, maximumBytes: 4096, partialMessages: &partialMessages)
    let validDelta = HuskyChatEvent.textDelta(
      requestID: nil, messageID: "m-1", revision: 1, append: "ed", replace: nil
    )
    try HuskyMessageBodyValidator.apply(
      validDelta, maximumBytes: 4096, partialMessages: &partialMessages)
    XCTAssertEqual(partialMessages["m-1"]?.text, "started")

    let attributedDelta = HuskyChatEvent.textDelta(
      requestID: "r-1", messageID: "m-1", revision: 2, append: "wrong", replace: nil
    )
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        attributedDelta, maximumBytes: 4096, partialMessages: &partialMessages)
    )
    XCTAssertEqual(partialMessages["m-1"]?.text, "started")
  }

  func testHistoryAndCompletedMessageTextUseTheUTF8ByteLimit() throws {
    XCTAssertThrowsError(try HuskyMessageBodyValidator.validate("éé", maximumBytes: 3))

    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    let completed = HuskyChatEvent.messageCompleted(
      requestID: "r-1",
      message: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .assistant, text: "éé",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 2
      )
    )
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        completed, maximumBytes: 3, partialMessages: &partialMessages)
    )
  }

  func testEventBufferOverflowTerminatesWithExplicitError() async throws {
    let buffer = HuskyEventStreamBuffer(capacity: 1)
    let first = HuskySequencedEvent(
      sequence: 1,
      event: .statusChanged(requestID: "r-1", status: .thinking, detail: "")
    )
    let dropped = HuskySequencedEvent(
      sequence: 2,
      event: .statusChanged(requestID: "r-1", status: .typing, detail: "")
    )
    XCTAssertEqual(buffer.yield(first), .buffered)
    XCTAssertEqual(buffer.yield(dropped), .overflow)

    var iterator = buffer.stream.makeAsyncIterator()
    let buffered = try await iterator.next()
    XCTAssertEqual(buffered, first)
    do {
      _ = try await iterator.next()
      XCTFail("overflow must terminate the stream with an error")
    } catch {
      XCTAssertEqual(error as? HuskyClientError, .eventBufferOverflow)
    }
  }

  func testCancellingEventConsumerRunsTerminationHandler() async {
    let buffer = HuskyEventStreamBuffer(capacity: 1)
    let handlerFinished = expectation(description: "event consumer termination handled")
    buffer.onTermination { termination in
      if case .cancelled = termination {
        handlerFinished.fulfill()
      }
    }
    let consumer = Task {
      var iterator = buffer.stream.makeAsyncIterator()
      _ = try? await iterator.next()
    }

    consumer.cancel()
    await fulfillment(of: [handlerFinished], timeout: 1)
    await consumer.value
  }

  func testCommandStreamIsBoundedAndTerminatesAfterOverflow() async throws {
    let commands = HuskyCommandStream(capacity: 1)
    var command = HuskyClientCommand()
    command.command = .endSession(HuskyEndSession())

    XCTAssertEqual(commands.yield(command), .enqueued)
    XCTAssertEqual(commands.yield(command), .overflow)
    var iterator = commands.stream.makeAsyncIterator()
    let buffered = try await iterator.next()
    XCTAssertEqual(buffered, command)
    let finished = try await iterator.next()
    XCTAssertNil(finished)
  }

  func testLiveMessageMustMatchSessionConversation() {
    let event = HuskyChatEvent.messageStarted(
      requestID: "r-1",
      message: HuskyMessage(
        id: "m-1", conversationID: "other-conversation", role: .assistant, text: "hello",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 1
      )
    )
    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        event,
        maximumBytes: 4096,
        expectedConversationID: "selected-conversation",
        partialMessages: &partialMessages
      )
    ) { error in
      XCTAssertEqual(
        error as? HuskyClientError,
        .unexpectedConversation(expected: "selected-conversation", actual: "other-conversation")
      )
    }
  }

  func testMessageStartedAndCompletedRejectNestedRequestIDMismatch() {
    let message = HuskyMessage(
      id: "m-1", conversationID: "c-1", role: .assistant, text: "hello",
      createdAt: Date(timeIntervalSince1970: 0), requestID: "r-2", sequence: 1
    )
    let mismatchedEvents: [HuskyChatEvent] = [
      .messageStarted(requestID: "r-1", message: message),
      .messageCompleted(requestID: "r-1", message: message),
    ]

    for event in mismatchedEvents {
      var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
      XCTAssertThrowsError(
        try HuskyMessageBodyValidator.apply(
          event, maximumBytes: 4096, partialMessages: &partialMessages)
      ) { error in
        XCTAssertEqual(
          error as? HuskyClientError,
          .malformedResponse(
            "message lifecycle request ID does not match nested message request ID")
        )
      }
      XCTAssertTrue(partialMessages.isEmpty)
    }
  }

  func testUnsolicitedMessageStartedAndCompletedAllowMatchingNilRequestIDs() throws {
    let message = HuskyMessage(
      id: "m-1", conversationID: "c-1", role: .assistant, text: "hello",
      createdAt: Date(timeIntervalSince1970: 0), requestID: nil, sequence: 1
    )
    var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
    try HuskyMessageBodyValidator.apply(
      .messageStarted(requestID: nil, message: message),
      maximumBytes: 4096,
      partialMessages: &partialMessages
    )
    XCTAssertNil(partialMessages["m-1"]?.requestID)

    try HuskyMessageBodyValidator.apply(
      .messageCompleted(requestID: nil, message: message),
      maximumBytes: 4096,
      partialMessages: &partialMessages
    )
    XCTAssertNil(partialMessages["m-1"])
  }

  func testRequestCancellationAndFailureClearPartialMessages() throws {
    for terminalEvent in [
      HuskyChatEvent.requestCancelled(requestID: "r-1"),
      HuskyChatEvent.requestFailed(
        requestID: "r-1", publicCode: "FAILED_PRECONDITION", message: "stopped", retryable: false
      ),
    ] {
      var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
      let started = HuskyChatEvent.messageStarted(
        requestID: "r-1",
        message: HuskyMessage(
          id: "m-1", conversationID: "c-1", role: .assistant, text: "partial",
          createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 1
        )
      )
      try HuskyMessageBodyValidator.apply(
        started, maximumBytes: 4096, partialMessages: &partialMessages)
      XCTAssertNotNil(partialMessages["m-1"])

      try HuskyMessageBodyValidator.apply(
        terminalEvent, maximumBytes: 4096, partialMessages: &partialMessages)
      XCTAssertNil(partialMessages["m-1"])
    }
  }

  func testNonReplayMessageAcceptanceRequiresPositiveSequence() throws {
    let acceptedMessage = HuskyMessage(
      id: "m-1", conversationID: "c-1", role: .user, text: "hello",
      createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 0
    )
    let accepted = HuskyChatEvent.messageAccepted(
      requestID: "r-1", userMessage: acceptedMessage, replayed: false
    )
    XCTAssertThrowsError(try HuskyGRPCMapper.validateEventSequence(0, for: accepted)) { error in
      XCTAssertEqual(error as? HuskyClientError, .invalidEventSequence(expected: 1, actual: 0))
    }

    let acceptedWithSequence = HuskyChatEvent.messageAccepted(
      requestID: "r-1",
      userMessage: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .user, text: "hello",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 7
      ),
      replayed: false
    )
    XCTAssertNoThrow(try HuskyGRPCMapper.validateEventSequence(7, for: acceptedWithSequence))
    XCTAssertThrowsError(try HuskyGRPCMapper.validateEventSequence(8, for: acceptedWithSequence)) {
      error in
      XCTAssertEqual(error as? HuskyClientError, .invalidEventSequence(expected: 7, actual: 8))
    }

    let replayed = HuskyChatEvent.messageAccepted(
      requestID: "r-1",
      userMessage: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .user, text: "hello",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 7
      ),
      replayed: true
    )
    XCTAssertNoThrow(try HuskyGRPCMapper.validateEventSequence(0, for: replayed))
  }

  func testMessageAcceptedRequiresMatchingEnvelopeAndMessageRequestIDs() {
    let accepted = HuskyChatEvent.messageAccepted(
      requestID: "r-1",
      userMessage: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .user, text: "hello",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-2", sequence: 7
      ),
      replayed: false
    )

    XCTAssertThrowsError(try HuskyGRPCMapper.validateEventSequence(7, for: accepted)) { error in
      XCTAssertEqual(
        error as? HuskyClientError,
        .malformedResponse("accepted message request ID does not match event request ID")
      )
    }
  }

  func testMessageStartedRequiresEnvelopeSequenceToMatchNestedMessage() {
    let started = HuskyChatEvent.messageStarted(
      requestID: "r-1",
      message: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .assistant, text: "hello",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 9
      )
    )

    XCTAssertThrowsError(try HuskyGRPCMapper.validateEventSequence(10, for: started)) { error in
      XCTAssertEqual(error as? HuskyClientError, .invalidEventSequence(expected: 9, actual: 10))
    }
  }

  func testMessageCompletedRequiresEnvelopeSequenceToMatchNestedMessage() {
    let completed = HuskyChatEvent.messageCompleted(
      requestID: "r-1",
      message: HuskyMessage(
        id: "m-1", conversationID: "c-1", role: .assistant, text: "hello",
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 9
      )
    )

    XCTAssertThrowsError(try HuskyGRPCMapper.validateEventSequence(10, for: completed)) { error in
      XCTAssertEqual(error as? HuskyClientError, .invalidEventSequence(expected: 9, actual: 10))
    }
  }

  func testUnaryRPCDeadlineIsBoundedAndShared() {
    XCTAssertEqual(HuskyGRPCMapper.unaryCallOptions.timeout, .seconds(15))
  }

  private func validCapabilities() -> HuskyGetCapabilitiesResponse {
    var response = HuskyGetCapabilitiesResponse()
    response.protocolVersion = "husky.v1"
    response.minimumClientMajor = 1
    response.maximumClientMajor = 1
    response.maximumMessageUtf8Bytes = 4096
    response.defaultHistoryPageSize = 20
    response.maximumHistoryPageSize = 50
    return response
  }
}
