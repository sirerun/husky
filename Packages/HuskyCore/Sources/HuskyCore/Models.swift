import Foundation

public struct HuskyCapabilities: Sendable, Equatable {
  public let protocolVersion: String
  public let minimumClientMajor: UInt32
  public let maximumClientMajor: UInt32
  public let maximumMessageUTF8Bytes: UInt32
  public let defaultHistoryPageSize: UInt32
  public let maximumHistoryPageSize: UInt32
  public let features: Set<String>

  public init(
    protocolVersion: String,
    minimumClientMajor: UInt32,
    maximumClientMajor: UInt32,
    maximumMessageUTF8Bytes: UInt32,
    defaultHistoryPageSize: UInt32,
    maximumHistoryPageSize: UInt32,
    features: Set<String>
  ) {
    self.protocolVersion = protocolVersion
    self.minimumClientMajor = minimumClientMajor
    self.maximumClientMajor = maximumClientMajor
    self.maximumMessageUTF8Bytes = maximumMessageUTF8Bytes
    self.defaultHistoryPageSize = defaultHistoryPageSize
    self.maximumHistoryPageSize = maximumHistoryPageSize
    self.features = features
  }
}

public struct HuskyConversation: Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let createdAt: Date
  public let updatedAt: Date

  public init(id: String, title: String, createdAt: Date, updatedAt: Date) {
    self.id = id
    self.title = title
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public enum HuskyMessageRole: Sendable, Equatable {
  case user
  case assistant
  case system
}

public struct HuskyMessage: Sendable, Equatable, Identifiable {
  public let id: String
  public let conversationID: String
  public let role: HuskyMessageRole
  public let text: String
  public let createdAt: Date
  public let requestID: String?
  public let sequence: UInt64

  public init(
    id: String,
    conversationID: String,
    role: HuskyMessageRole,
    text: String,
    createdAt: Date,
    requestID: String?,
    sequence: UInt64
  ) {
    self.id = id
    self.conversationID = conversationID
    self.role = role
    self.text = text
    self.createdAt = createdAt
    self.requestID = requestID
    self.sequence = sequence
  }
}

public struct HuskyConversationPage: Sendable, Equatable {
  public let conversations: [HuskyConversation]
  public let nextCursor: String?
  public let hasMore: Bool

  public init(conversations: [HuskyConversation], nextCursor: String?, hasMore: Bool) {
    self.conversations = conversations
    self.nextCursor = nextCursor
    self.hasMore = hasMore
  }
}

public struct HuskyHistoryPage: Sendable, Equatable {
  public let messages: [HuskyMessage]
  public let nextCursor: String?
  public let hasMore: Bool
  public let snapshotSequence: UInt64

  public init(
    messages: [HuskyMessage],
    nextCursor: String?,
    hasMore: Bool,
    snapshotSequence: UInt64
  ) {
    self.messages = messages
    self.nextCursor = nextCursor
    self.hasMore = hasMore
    self.snapshotSequence = snapshotSequence
  }
}

public enum HuskyBackendStatus: Sendable, Equatable {
  case thinking
  case typing
  case waiting
  case idle
  case error
  case unknown(Int)
}

public enum HuskyChatEvent: Sendable, Equatable {
  case sessionReady(conversationID: String, caughtUpThrough: UInt64, resumeToken: String?)
  case messageAccepted(requestID: String, userMessage: HuskyMessage, replayed: Bool)
  case messageStarted(requestID: String?, message: HuskyMessage)
  case textDelta(
    requestID: String?, messageID: String, revision: UInt64, append: String, replace: String?)
  case messageCompleted(requestID: String?, message: HuskyMessage)
  case statusChanged(requestID: String?, status: HuskyBackendStatus, detail: String)
  case requestCancelled(requestID: String)
  case requestFailed(requestID: String, publicCode: String, message: String, retryable: Bool)
  case resyncRequired(conversationID: String, oldestAvailableSequence: UInt64, reason: String)

}

public enum HuskyClientError: Error, Sendable, Equatable {
  case invalidIdentifier
  case invalidPageSize(requested: UInt32, maximum: UInt32)
  case messageTooLarge(actualUTF8Bytes: Int, maximum: UInt32)
  case unsupportedMessageRole(Int)
  case unsupportedProtocolVersion(String)
  case incompatibleClientVersion(minimum: UInt32, maximum: UInt32, client: UInt32)
  case unexpectedConversation(expected: String, actual: String)
  case invalidEventSequence(expected: UInt64, actual: UInt64)
  case eventApplicationPending(sequence: UInt64)
  case eventNotPending
  case historyNotOrdered
  case malformedResponse(String)
  case invalidCapabilities(String)
  case eventBufferOverflow
  case resynchronizationRequired
}
