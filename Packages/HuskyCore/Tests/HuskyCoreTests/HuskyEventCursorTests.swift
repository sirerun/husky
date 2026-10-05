import XCTest

@testable import HuskyCore

final class HuskyEventCursorTests: XCTestCase {
  func testCursorAdvancesOnlyAfterAcknowledgementAndIgnoresReplay() throws {
    var cursor = HuskyEventCursor(conversationID: "c-1", afterSequence: 4)
    let sequencedEvent = HuskySequencedEvent(
      sequence: 5,
      event: .messageStarted(
        requestID: "r-1",
        message: HuskyMessage(
          id: "m-1", conversationID: "c-1", role: .assistant, text: "",
          createdAt: Date(timeIntervalSince1970: 0), requestID: "r-1", sequence: 5
        )
      ))

    XCTAssertEqual(try cursor.stage(sequencedEvent), .deliver)
    XCTAssertEqual(cursor.lastAppliedSequence, 4)
    XCTAssertThrowsError(try cursor.stage(sequencedEvent)) {
      XCTAssertEqual($0 as? HuskyClientError, .eventApplicationPending(sequence: 5))
    }
    try cursor.acknowledge(sequencedEvent)
    XCTAssertEqual(cursor.lastAppliedSequence, 5)
    XCTAssertEqual(try cursor.stage(sequencedEvent), .ignoreDuplicate)
    XCTAssertEqual(
      try cursor.stage(.init(sequence: 7, event: sequencedEvent.event)), .resynchronize)
    XCTAssertEqual(cursor.lastAppliedSequence, 5)
  }

  func testSessionReadyMatchesAppliedWatermarkAndUpdatesToken() throws {
    var cursor = HuskyEventCursor(conversationID: "c-1", afterSequence: 8)
    let ready = HuskyChatEvent.sessionReady(
      conversationID: "c-1", caughtUpThrough: 8, resumeToken: "resume-8"
    )

    let readyEvent = HuskySequencedEvent(sequence: 0, event: ready)
    XCTAssertEqual(try cursor.stage(readyEvent), .deliver)
    XCTAssertEqual(cursor.lastAppliedSequence, 8)
    XCTAssertNil(cursor.resumeToken)
    try cursor.acknowledge(readyEvent)
    XCTAssertEqual(cursor.resumeToken, "resume-8")
    let skippedReplay = HuskyChatEvent.sessionReady(
      conversationID: "c-1", caughtUpThrough: 10, resumeToken: "resume-10"
    )
    XCTAssertEqual(try cursor.stage(.init(sequence: 0, event: skippedReplay)), .resynchronize)
  }

  func testExpiredCursorRequiresCanonicalResync() throws {
    var cursor = HuskyEventCursor(conversationID: "c-1", afterSequence: 18)
    let resync = HuskyChatEvent.resyncRequired(
      conversationID: "c-1", oldestAvailableSequence: 24, reason: "expired"
    )

    XCTAssertEqual(try cursor.stage(.init(sequence: 0, event: resync)), .resynchronize)
    cursor.reset(after: 23)
    XCTAssertEqual(cursor.lastAppliedSequence, 23)
    XCTAssertNil(cursor.resumeToken)
  }

  func testRejectsControlResponseFromAnotherConversation() {
    var cursor = HuskyEventCursor(conversationID: "c-1", afterSequence: 0)
    let ready = HuskyChatEvent.sessionReady(
      conversationID: "c-2", caughtUpThrough: 0, resumeToken: nil
    )

    XCTAssertThrowsError(try cursor.stage(.init(sequence: 0, event: ready))) {
      XCTAssertEqual(
        $0 as? HuskyClientError, .unexpectedConversation(expected: "c-1", actual: "c-2"))
    }
  }
}
