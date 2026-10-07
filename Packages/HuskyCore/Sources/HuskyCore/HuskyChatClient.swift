import Foundation

public protocol HuskyConversationSession: Sendable {
  /// A failed stream is surfaced here. Reopen it with the latest fully applied
  /// cursor and its resume token; if a `resyncRequired` event arrives, fetch
  /// canonical history and open a new stream at that page's snapshot sequence.
  var events: AsyncThrowingStream<HuskySequencedEvent, any Error> { get }

  /// Reuse the same request ID and exact text if an earlier submission has an
  /// ambiguous transport outcome. Do not generate a new ID for that retry.
  func submit(requestID: String, text: String) async throws
  func cancel(requestID: String) async throws
  func end() async
}

public protocol HuskyChatClient: Sendable {
  /// A client instance is scoped to one saved backend profile; conversation
  /// IDs from another profile must never be used with this client.
  func getCapabilities() async throws -> HuskyCapabilities

  func listConversations(pageSize: UInt32, before cursor: String?) async throws
    -> HuskyConversationPage

  /// `requestID` is the idempotency key and must remain stable across retries.
  func createConversation(requestID: String, title: String) async throws -> HuskyConversation

  func getHistory(
    conversationID: String,
    pageSize: UInt32,
    before cursor: String?
  ) async throws -> HuskyHistoryPage

  /// Open after the last fully applied event. The initial history fetch should
  /// pass its `snapshotSequence` here to close the history/stream race.
  func openConversation(
    conversationID: String,
    afterSequence: UInt64,
    resumeToken: String?
  ) async throws -> any HuskyConversationSession

  func openConversation(
    conversationID: String, afterSequence: UInt64, resumeToken: String?,
    partialMessages: [HuskyPartialMessageSnapshot]
  ) async throws -> any HuskyConversationSession
}

extension HuskyChatClient {
  public func openConversation(
    conversationID: String, afterSequence: UInt64, resumeToken: String?,
    partialMessages: [HuskyPartialMessageSnapshot]
  ) async throws -> any HuskyConversationSession {
    guard partialMessages.isEmpty else {
      throw HuskyPartialRecoveryError.unsupportedAdapter
    }
    return try await openConversation(
      conversationID: conversationID, afterSequence: afterSequence, resumeToken: resumeToken)
  }
}

public struct HuskySequencedEvent: Sendable, Equatable {
  public let sequence: UInt64
  public let event: HuskyChatEvent

  public init(sequence: UInt64, event: HuskyChatEvent) {
    self.sequence = sequence
    self.event = event
  }
}

public enum HuskyEventDisposition: Sendable, Equatable {
  case deliver
  case ignoreDuplicate
  case resynchronize
}

/// Tracks the last fully applied event for one conversation and rejects gaps.
/// A caller must fetch canonical history and start a new stream after a gap or
/// a server `ResyncRequired`; it must not apply later events to stale state.
public struct HuskyEventCursor: Sendable, Equatable {
  public let conversationID: String
  public private(set) var lastAppliedSequence: UInt64
  public private(set) var resumeToken: String?
  private var pendingEvent: HuskySequencedEvent?
  private var pendingResumeToken: String?

  public init(conversationID: String, afterSequence: UInt64, resumeToken: String? = nil) {
    self.conversationID = conversationID
    self.lastAppliedSequence = afterSequence
    self.resumeToken = resumeToken
  }

  /// Validates an event without advancing the reconnect cursor. The consumer
  /// must call `acknowledge(_:)` only after it has applied the event to state.
  public mutating func stage(_ sequencedEvent: HuskySequencedEvent) throws -> HuskyEventDisposition
  {
    guard self.pendingEvent == nil else {
      throw HuskyClientError.eventApplicationPending(
        sequence: self.pendingEvent?.sequence ?? self.lastAppliedSequence
      )
    }
    switch sequencedEvent.event {
    case .sessionReady(let conversationID, let caughtUpThrough, let token):
      guard conversationID == self.conversationID else {
        throw HuskyClientError.unexpectedConversation(
          expected: self.conversationID, actual: conversationID)
      }
      // The server sends SessionReady after replaying retained events, so the
      // watermark must equal the cursor already applied by the consumer.
      // A mismatch means some replay events were lost or skipped.
      guard caughtUpThrough == self.lastAppliedSequence else {
        return .resynchronize
      }
      self.pendingEvent = sequencedEvent
      self.pendingResumeToken = token
      return .deliver

    case .resyncRequired(let conversationID, _, _):
      guard conversationID == self.conversationID else {
        throw HuskyClientError.unexpectedConversation(
          expected: self.conversationID, actual: conversationID)
      }
      return .resynchronize

    default:
      break
    }

    let sequence = sequencedEvent.sequence
    guard sequence > 0 else {
      self.pendingEvent = sequencedEvent
      return .deliver
    }
    guard sequence > self.lastAppliedSequence else { return .ignoreDuplicate }
    let (expected, overflow) = self.lastAppliedSequence.addingReportingOverflow(1)
    guard !overflow, sequence == expected else { return .resynchronize }
    self.pendingEvent = sequencedEvent
    return .deliver
  }

  public mutating func acknowledge(_ sequencedEvent: HuskySequencedEvent) throws {
    guard self.pendingEvent == sequencedEvent else {
      throw HuskyClientError.eventNotPending
    }
    if sequencedEvent.sequence > 0 {
      self.lastAppliedSequence = sequencedEvent.sequence
    }
    if case .sessionReady = sequencedEvent.event {
      self.resumeToken = self.pendingResumeToken
    }
    self.pendingEvent = nil
    self.pendingResumeToken = nil
  }

  public mutating func reset(after snapshotSequence: UInt64, resumeToken: String? = nil) {
    self.lastAppliedSequence = snapshotSequence
    self.resumeToken = resumeToken
    self.pendingEvent = nil
    self.pendingResumeToken = nil
  }
}
