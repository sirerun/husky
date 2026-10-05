import XCTest
@testable import HuskyCore
import HuskyProtocol

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
      try HuskyMessageBodyValidator.apply(tooLarge, maximumBytes: 3, partialMessages: &partialMessages)
    )

    let replacement = HuskyChatEvent.textDelta(
      requestID: "r-1", messageID: "m-1", revision: 2, append: "ignored", replace: "é"
    )
    try HuskyMessageBodyValidator.apply(replacement, maximumBytes: 3, partialMessages: &partialMessages)
    XCTAssertEqual(partialMessages["m-1"]?.text, "é")
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(replacement, maximumBytes: 3, partialMessages: &partialMessages)
    )
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
      try HuskyMessageBodyValidator.apply(completed, maximumBytes: 3, partialMessages: &partialMessages)
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
