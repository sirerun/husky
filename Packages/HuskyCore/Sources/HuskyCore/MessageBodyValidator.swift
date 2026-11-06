import Foundation

enum HuskyMessageBodyValidator {
  struct PartialMessage: Sendable {
    var revision: UInt64
    var text: String
    var requestID: String?
  }

  static func seed(
    _ snapshots: [HuskyPartialMessageSnapshot], conversationID: String,
    afterSequence: UInt64, maximumBytes: UInt32
  ) throws -> [String: PartialMessage] {
    guard snapshots.count <= 64 else {
      throw HuskyClientError.malformedResponse("too many partial message snapshots")
    }
    var result: [String: PartialMessage] = [:]
    var totalBytes = 0
    for snapshot in snapshots {
      let message = snapshot.message
      try HuskyGRPCMapper.validateIdentifier(message.id)
      try HuskyGRPCMapper.validateIdentifier(message.conversationID)
      if let requestID = message.requestID { try HuskyGRPCMapper.validateIdentifier(requestID) }
      try validateConversation(message, expected: conversationID)
      try validate(message.text, maximumBytes: maximumBytes)
      totalBytes += message.text.utf8.count
      guard totalBytes <= 2 * 1024 * 1024, message.sequence > 0,
        message.sequence <= afterSequence, message.role != .user, result[message.id] == nil
      else {
        throw HuskyClientError.malformedResponse("invalid partial message snapshot")
      }
      result[message.id] = PartialMessage(
        revision: snapshot.revision, text: message.text, requestID: message.requestID)
    }
    return result
  }

  static func validate(_ text: String, maximumBytes: UInt32) throws {
    let byteCount = text.utf8.count
    guard byteCount <= Int(maximumBytes) else {
      throw HuskyClientError.messageTooLarge(actualUTF8Bytes: byteCount, maximum: maximumBytes)
    }
  }

  static func apply(
    _ event: HuskyChatEvent,
    maximumBytes: UInt32,
    expectedConversationID: String? = nil,
    partialMessages: inout [String: PartialMessage]
  ) throws {
    switch event {
    case .messageAccepted(_, let message, _):
      try validateConversation(message, expected: expectedConversationID)
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages.removeValue(forKey: message.id)

    case .messageStarted(let requestID, let message):
      try validateLifecycleRequestID(requestID, nested: message.requestID)
      try validateConversation(message, expected: expectedConversationID)
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages[message.id] = PartialMessage(
        revision: 0,
        text: message.text,
        requestID: requestID
      )

    case .messageCompleted(let requestID, let message):
      try validateLifecycleRequestID(requestID, nested: message.requestID)
      try validateConversation(message, expected: expectedConversationID)
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages.removeValue(forKey: message.id)

    case .textDelta(let requestID, let messageID, let revision, let append, let replace):
      guard var partial = partialMessages[messageID] else {
        throw HuskyPartialRecoveryError.missingBaseline
      }
      guard requestID == partial.requestID else {
        throw HuskyClientError.malformedResponse(
          "text delta request ID does not match message start")
      }
      if let replace {
        try validate(replace, maximumBytes: maximumBytes)
      } else {
        try validate(append, maximumBytes: maximumBytes)
      }
      guard revision > partial.revision else {
        throw HuskyClientError.malformedResponse("text delta revisions must increase")
      }
      partial.text = replace ?? partial.text + append
      try validate(partial.text, maximumBytes: maximumBytes)
      partial.revision = revision
      partialMessages[messageID] = partial

    case .requestCancelled(let requestID), .requestFailed(let requestID, _, _, _):
      for (messageID, partial) in Array(partialMessages) where partial.requestID == requestID {
        partialMessages.removeValue(forKey: messageID)
      }

    case .sessionReady, .statusChanged, .resyncRequired:
      break
    }
  }

  private static func validateConversation(_ message: HuskyMessage, expected: String?) throws {
    guard let expected, message.conversationID != expected else { return }
    throw HuskyClientError.unexpectedConversation(
      expected: expected, actual: message.conversationID)
  }

  private static func validateLifecycleRequestID(_ eventID: String?, nested: String?) throws {
    guard eventID == nested else {
      throw HuskyClientError.malformedResponse(
        "message lifecycle request ID does not match nested message request ID")
    }
  }
}
