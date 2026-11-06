import Foundation
import XCTest

@testable import HuskyCore

final class HuskyPartialSnapshotTests: XCTestCase {
  func testSeedRetainsExactRevisionAndEnforcesCumulativeLimit() throws {
    var state = try HuskyMessageBodyValidator.seed(
      [snapshot(text: "abcd", revision: 4)], conversationID: "c", afterSequence: 7, maximumBytes: 5)
    XCTAssertEqual(state["m"]?.revision, 4)
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        .textDelta(requestID: "r", messageID: "m", revision: 4, append: "e", replace: nil),
        maximumBytes: 5, expectedConversationID: "c", partialMessages: &state))
    try HuskyMessageBodyValidator.apply(
      .textDelta(requestID: "r", messageID: "m", revision: 5, append: "e", replace: nil),
      maximumBytes: 5, expectedConversationID: "c", partialMessages: &state)
    XCTAssertEqual(state["m"]?.text, "abcde")
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.apply(
        .textDelta(requestID: "r", messageID: "m", revision: 6, append: "f", replace: nil),
        maximumBytes: 5, expectedConversationID: "c", partialMessages: &state))
  }

  func testSeedRejectsWrongScopeFutureDuplicateAndOversize() throws {
    let valid = snapshot(text: "a", revision: 0)
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.seed(
        [valid], conversationID: "other", afterSequence: 7, maximumBytes: 10))
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.seed(
        [valid], conversationID: "c", afterSequence: 6, maximumBytes: 10))
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.seed(
        [valid, valid], conversationID: "c", afterSequence: 7, maximumBytes: 10))
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.seed(
        [snapshot(text: "é", revision: 0)], conversationID: "c", afterSequence: 7, maximumBytes: 1))
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.seed(
        Array(repeating: valid, count: 65), conversationID: "c", afterSequence: 7, maximumBytes: 10)
    )
    let large = (0..<64).map { index in
      snapshot(id: "m-\(index)", text: String(repeating: "x", count: 32769), revision: 0)
    }
    XCTAssertThrowsError(
      try HuskyMessageBodyValidator.seed(
        large, conversationID: "c", afterSequence: 7, maximumBytes: 65536))
  }

  private func snapshot(id: String = "m", text: String, revision: UInt64)
    -> HuskyPartialMessageSnapshot
  {
    .init(
      message: .init(
        id: id, conversationID: "c", role: .assistant, text: text,
        createdAt: Date(timeIntervalSince1970: 0), requestID: "r", sequence: 7), revision: revision)
  }
}
