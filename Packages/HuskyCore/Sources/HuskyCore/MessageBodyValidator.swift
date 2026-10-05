import Foundation

enum HuskyMessageBodyValidator {
  struct PartialMessage: Sendable {
    var revision: UInt64
    var text: String
    var requestID: String?
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
    case .messageAccepted(_, let message, _), .messageCompleted(_, let message):
      try validateConversation(message, expected: expectedConversationID)
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages.removeValue(forKey: message.id)

    case .messageStarted(let requestID, let message):
      try validateConversation(message, expected: expectedConversationID)
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages[message.id] = PartialMessage(
        revision: 0,
        text: message.text,
        requestID: requestID
      )

    case .textDelta(let requestID, let messageID, let revision, let append, let replace):
      guard var partial = partialMessages[messageID] else {
        throw HuskyClientError.malformedResponse("text delta arrived before message start")
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
}
