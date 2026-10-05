import Foundation

enum HuskyMessageBodyValidator {
  struct PartialMessage: Sendable {
    var revision: UInt64
    var text: String
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
    partialMessages: inout [String: PartialMessage]
  ) throws {
    switch event {
    case let .messageAccepted(_, message, _), let .messageCompleted(_, message):
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages.removeValue(forKey: message.id)

    case let .messageStarted(_, message):
      try validate(message.text, maximumBytes: maximumBytes)
      partialMessages[message.id] = PartialMessage(revision: 0, text: message.text)

    case let .textDelta(_, messageID, revision, append, replace):
      if let replace {
        try validate(replace, maximumBytes: maximumBytes)
      } else {
        try validate(append, maximumBytes: maximumBytes)
      }
      var partial = partialMessages[messageID] ?? PartialMessage(revision: 0, text: "")
      guard revision > partial.revision else {
        throw HuskyClientError.malformedResponse("text delta revisions must increase")
      }
      partial.text = replace ?? partial.text + append
      try validate(partial.text, maximumBytes: maximumBytes)
      partial.revision = revision
      partialMessages[messageID] = partial

    case .sessionReady, .statusChanged, .requestCancelled, .requestFailed, .resyncRequired:
      break
    }
  }
}
