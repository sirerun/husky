import Foundation
import GRPCCore
import HuskyProtocol

/// Adapter from the generated gRPC Swift 2 client to Husky's app-facing API.
/// The caller owns the transport, so TLS, local-fixture plaintext selection,
/// connection metadata, and credential storage stay at the profile boundary.
public struct GRPCHuskyChatClient<Transport: ClientTransport>: HuskyChatClient {
  private let backend: HuskyHuskyBackend.Client<Transport>

  public init(backend: HuskyHuskyBackend.Client<Transport>) {
    self.backend = backend
  }

  public func getCapabilities() async throws -> HuskyCapabilities {
    let response = try await self.backend.getCapabilities(
      HuskyGetCapabilitiesRequest(), options: HuskyGRPCMapper.unaryCallOptions)
    return try HuskyGRPCMapper.mapCapabilities(response)
  }

  public func listConversations(pageSize: UInt32, before cursor: String?) async throws
    -> HuskyConversationPage
  {
    let capabilities = try await self.getCapabilities()
    try Self.validatePageSize(pageSize, maximum: capabilities.maximumHistoryPageSize)
    var request = HuskyListConversationsRequest()
    request.pageSize = pageSize
    request.beforeCursor = cursor ?? ""
    let response = try await self.backend.listConversations(
      request, options: HuskyGRPCMapper.unaryCallOptions)
    return HuskyConversationPage(
      conversations: try response.conversations.map(Self.mapConversation),
      nextCursor: response.nextCursor.isEmpty ? nil : response.nextCursor,
      hasMore: response.hasMore_p
    )
  }

  public func createConversation(requestID: String, title: String) async throws -> HuskyConversation
  {
    try Self.validateIdentifier(requestID)
    var request = HuskyCreateConversationRequest()
    request.clientRequestID = requestID
    request.title = title
    let response = try await self.backend.createConversation(
      request, options: HuskyGRPCMapper.unaryCallOptions)
    return try Self.mapConversation(response.conversation)
  }

  public func getHistory(
    conversationID: String,
    pageSize: UInt32,
    before cursor: String?
  ) async throws -> HuskyHistoryPage {
    try Self.validateIdentifier(conversationID)
    let capabilities = try await self.getCapabilities()
    try Self.validatePageSize(pageSize, maximum: capabilities.maximumHistoryPageSize)
    var request = HuskyGetHistoryRequest()
    request.conversationID = conversationID
    request.pageSize = pageSize
    request.beforeCursor = cursor ?? ""
    let response = try await self.backend.getHistory(
      request, options: HuskyGRPCMapper.unaryCallOptions)
    let messages = try response.messages.map { message in
      try Self.mapMessage(
        message,
        expectedConversationID: conversationID,
        maximumMessageBytes: capabilities.maximumMessageUTF8Bytes
      )
    }
    guard zip(messages, messages.dropFirst()).allSatisfy({ $0.0.sequence < $0.1.sequence }) else {
      throw HuskyClientError.historyNotOrdered
    }
    return HuskyHistoryPage(
      messages: messages,
      nextCursor: response.nextCursor.isEmpty ? nil : response.nextCursor,
      hasMore: response.hasMore_p,
      snapshotSequence: response.snapshotSequence
    )
  }

  public func openConversation(
    conversationID: String,
    afterSequence: UInt64,
    resumeToken: String?
  ) async throws -> any HuskyConversationSession {
    try Self.validateIdentifier(conversationID)
    let capabilities = try await self.getCapabilities()
    return GRPCHuskyConversationSession(
      backend: self.backend,
      conversationID: conversationID,
      afterSequence: afterSequence,
      resumeToken: resumeToken,
      maximumMessageBytes: capabilities.maximumMessageUTF8Bytes
    )
  }

  static func validateIdentifier(_ identifier: String) throws {
    guard !identifier.isEmpty else { throw HuskyClientError.invalidIdentifier }
  }

  static func validatePageSize(_ pageSize: UInt32, maximum: UInt32) throws {
    guard pageSize == 0 || pageSize <= maximum else {
      throw HuskyClientError.invalidPageSize(requested: pageSize, maximum: maximum)
    }
  }

  static func mapConversation(_ conversation: HuskyConversationSummary) throws -> HuskyConversation
  {
    try validateIdentifier(conversation.conversationID)
    return HuskyConversation(
      id: conversation.conversationID,
      title: conversation.title,
      createdAt: Self.date(
        seconds: conversation.createdAt.seconds, nanos: conversation.createdAt.nanos),
      updatedAt: Self.date(
        seconds: conversation.updatedAt.seconds, nanos: conversation.updatedAt.nanos)
    )
  }

  static func mapMessage(
    _ message: HuskyChatMessage,
    expectedConversationID: String? = nil,
    maximumMessageBytes: UInt32
  ) throws -> HuskyMessage {
    try validateIdentifier(message.messageID)
    try validateIdentifier(message.conversationID)
    if let expectedConversationID, message.conversationID != expectedConversationID {
      throw HuskyClientError.unexpectedConversation(
        expected: expectedConversationID,
        actual: message.conversationID
      )
    }
    try HuskyMessageBodyValidator.validate(message.text, maximumBytes: maximumMessageBytes)
    let role: HuskyMessageRole
    switch message.role {
    case .user: role = .user
    case .assistant: role = .assistant
    case .system: role = .system
    case .unspecified: throw HuskyClientError.unsupportedMessageRole(0)
    case .UNRECOGNIZED(let rawValue): throw HuskyClientError.unsupportedMessageRole(rawValue)
    }
    return HuskyMessage(
      id: message.messageID,
      conversationID: message.conversationID,
      role: role,
      text: message.text,
      createdAt: Self.date(seconds: message.createdAt.seconds, nanos: message.createdAt.nanos),
      requestID: message.requestID.isEmpty ? nil : message.requestID,
      sequence: message.sequence
    )
  }

  static func mapEvent(
    _ event: HuskyBackendEvent,
    maximumMessageBytes: UInt32
  ) throws -> HuskyChatEvent {
    switch event.event {
    case .sessionReady(let value):
      try validateIdentifier(value.conversationID)
      return .sessionReady(
        conversationID: value.conversationID,
        caughtUpThrough: value.caughtUpThroughSequence,
        resumeToken: value.resumeToken.isEmpty ? nil : value.resumeToken
      )
    case .messageAccepted(let value):
      try validateIdentifier(value.requestID)
      return .messageAccepted(
        requestID: value.requestID,
        userMessage: try mapMessage(value.userMessage, maximumMessageBytes: maximumMessageBytes),
        replayed: value.replayedIdempotentResult
      )
    case .messageStarted(let value):
      return .messageStarted(
        requestID: value.requestID.isEmpty ? nil : value.requestID,
        message: try mapMessage(value.message, maximumMessageBytes: maximumMessageBytes)
      )
    case .textDelta(let value):
      try validateIdentifier(value.messageID)
      if value.hasReplaceText {
        try HuskyMessageBodyValidator.validate(value.replaceText, maximumBytes: maximumMessageBytes)
      } else {
        try HuskyMessageBodyValidator.validate(value.appendText, maximumBytes: maximumMessageBytes)
      }
      return .textDelta(
        requestID: value.requestID.isEmpty ? nil : value.requestID,
        messageID: value.messageID,
        revision: value.revision,
        append: value.appendText,
        replace: value.hasReplaceText ? value.replaceText : nil
      )
    case .messageCompleted(let value):
      return .messageCompleted(
        requestID: value.requestID.isEmpty ? nil : value.requestID,
        message: try mapMessage(value.message, maximumMessageBytes: maximumMessageBytes)
      )
    case .statusChanged(let value):
      return .statusChanged(
        requestID: value.requestID.isEmpty ? nil : value.requestID,
        status: Self.mapStatus(value.status),
        detail: value.detail
      )
    case .requestCancelled(let value):
      try validateIdentifier(value.requestID)
      return .requestCancelled(requestID: value.requestID)
    case .requestFailed(let value):
      try validateIdentifier(value.requestID)
      return .requestFailed(
        requestID: value.requestID,
        publicCode: value.publicCode,
        message: value.message,
        retryable: value.retryable
      )
    case .resyncRequired(let value):
      try validateIdentifier(value.conversationID)
      return .resyncRequired(
        conversationID: value.conversationID,
        oldestAvailableSequence: value.oldestAvailableSequence,
        reason: value.reason
      )
    case nil:
      throw HuskyClientError.malformedResponse("backend event is missing its event payload")
    }
  }

  static func mapStatus(_ status: HuskyProtocol.HuskyBackendStatus) -> HuskyBackendStatus {
    switch status {
    case .thinking: return .thinking
    case .typing: return .typing
    case .waiting: return .waiting
    case .idle: return .idle
    case .error: return .error
    case .unspecified: return .error
    case .UNRECOGNIZED(let rawValue): return .unknown(rawValue)
    }
  }

  private static func date(seconds: Int64, nanos: Int32) -> Date {
    Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
  }
}

enum HuskyGRPCMapper {
  /// Shared deadline for every unary capability, conversation, and history RPC.
  static var unaryCallOptions: CallOptions {
    var options = CallOptions.defaults
    options.timeout = .seconds(15)
    return options
  }

  static func mapCapabilities(_ response: HuskyGetCapabilitiesResponse) throws -> HuskyCapabilities
  {
    guard response.protocolVersion == "husky.v1" else {
      throw HuskyClientError.unsupportedProtocolVersion(response.protocolVersion)
    }
    guard response.minimumClientMajor > 0,
      response.maximumClientMajor >= response.minimumClientMajor
    else {
      throw HuskyClientError.invalidCapabilities("client major range is empty or non-positive")
    }
    let clientMajor: UInt32 = 1
    guard response.minimumClientMajor <= clientMajor, clientMajor <= response.maximumClientMajor
    else {
      throw HuskyClientError.incompatibleClientVersion(
        minimum: response.minimumClientMajor,
        maximum: response.maximumClientMajor,
        client: clientMajor
      )
    }
    guard response.maximumMessageUtf8Bytes > 0,
      response.maximumMessageUtf8Bytes <= 64 * 1024
    else {
      throw HuskyClientError.invalidCapabilities("message byte limit must be between 1 and 65536")
    }
    guard response.maximumHistoryPageSize > 0,
      response.maximumHistoryPageSize <= 100
    else {
      throw HuskyClientError.invalidCapabilities(
        "maximum history page size must be between 1 and 100")
    }
    guard response.defaultHistoryPageSize > 0,
      response.defaultHistoryPageSize <= 50,
      response.defaultHistoryPageSize <= response.maximumHistoryPageSize
    else {
      throw HuskyClientError.invalidCapabilities(
        "default history page size must be between 1 and 50 and no greater than its maximum"
      )
    }
    return HuskyCapabilities(
      protocolVersion: response.protocolVersion,
      minimumClientMajor: response.minimumClientMajor,
      maximumClientMajor: response.maximumClientMajor,
      maximumMessageUTF8Bytes: response.maximumMessageUtf8Bytes,
      defaultHistoryPageSize: response.defaultHistoryPageSize,
      maximumHistoryPageSize: response.maximumHistoryPageSize,
      features: Set(response.features)
    )
  }

  static func validateEventSequence(_ sequence: UInt64, for event: HuskyChatEvent) throws {
    switch event {
    case .sessionReady, .resyncRequired:
      guard sequence == 0 else {
        throw HuskyClientError.invalidEventSequence(expected: 0, actual: sequence)
      }
    case .messageAccepted(let requestID, let message, let replayed):
      guard message.requestID == requestID else {
        throw HuskyClientError.malformedResponse(
          "accepted message request ID does not match event request ID")
      }
      guard message.sequence > 0 else {
        throw HuskyClientError.invalidEventSequence(expected: 1, actual: message.sequence)
      }
      let expected = replayed ? 0 : message.sequence
      guard sequence == expected else {
        throw HuskyClientError.invalidEventSequence(expected: expected, actual: sequence)
      }
    case .messageStarted(_, let message), .messageCompleted(_, let message):
      guard sequence > 0, sequence == message.sequence else {
        throw HuskyClientError.invalidEventSequence(expected: message.sequence, actual: sequence)
      }
    case .textDelta, .statusChanged:
      guard sequence > 0 else {
        throw HuskyClientError.invalidEventSequence(expected: 1, actual: sequence)
      }
    case .requestCancelled:
      // A cancellation after completion is an idempotent, cursor-neutral no-op acknowledgement.
      // A cancellation that changes state carries its normal positive event sequence.
      break
    case .requestFailed:
      // A failed-command reply uses zero. An asynchronous request failure may
      // be an ordinary sequenced conversation event.
      break
    }
  }
}

private final class GRPCHuskyConversationSession<Transport: ClientTransport>:
  HuskyConversationSession,
  @unchecked Sendable
{
  let events: AsyncThrowingStream<HuskySequencedEvent, any Error>
  private let conversationID: String
  private let maximumMessageBytes: UInt32
  private let commandStream: HuskyCommandStream
  private let eventBuffer: HuskyEventStreamBuffer
  private let rpcTaskControl: HuskyTaskCancellation
  private let rpcTask: Task<Void, Never>

  init(
    backend: HuskyHuskyBackend.Client<Transport>,
    conversationID: String,
    afterSequence: UInt64,
    resumeToken: String?,
    maximumMessageBytes: UInt32
  ) {
    let commandStream = HuskyCommandStream(capacity: 128)
    let eventBuffer = HuskyEventStreamBuffer(capacity: 128)
    self.events = eventBuffer.stream
    self.conversationID = conversationID
    self.maximumMessageBytes = maximumMessageBytes
    self.commandStream = commandStream
    self.eventBuffer = eventBuffer
    let rpcTaskControl = HuskyTaskCancellation()
    self.rpcTaskControl = rpcTaskControl
    let rpcTask = Task {
      do {
        try await backend.conversationSession { writer in
          var start = HuskyStartSession()
          start.conversationID = conversationID
          start.afterSequence = afterSequence
          start.resumeToken = resumeToken ?? ""
          var firstCommand = HuskyClientCommand()
          firstCommand.command = .startSession(start)
          try await writer.write(firstCommand)
          for await command in commandStream.stream {
            try await writer.write(command)
          }
        } onResponse: { response in
          var partialMessages: [String: HuskyMessageBodyValidator.PartialMessage] = [:]
          defer { partialMessages.removeAll() }
          for try await event in response.messages {
            do {
              let mapped = try GRPCHuskyChatClient<Transport>.mapEvent(
                event,
                maximumMessageBytes: maximumMessageBytes
              )
              try HuskyGRPCMapper.validateEventSequence(
                event.sequence,
                for: mapped
              )
              try HuskyMessageBodyValidator.apply(
                mapped,
                maximumBytes: maximumMessageBytes,
                expectedConversationID: conversationID,
                partialMessages: &partialMessages
              )
              switch eventBuffer.yield(HuskySequencedEvent(sequence: event.sequence, event: mapped))
              {
              case .buffered:
                break
              case .overflow, .terminated:
                commandStream.finish()
                eventBuffer.finish(throwing: HuskyClientError.eventBufferOverflow)
                rpcTaskControl.cancel()
                return
              }
              if case .resyncRequired = mapped {
                commandStream.finish()
                eventBuffer.finish()
                rpcTaskControl.cancel()
                return
              }
            } catch {
              commandStream.finish()
              eventBuffer.finish(throwing: error)
              rpcTaskControl.cancel()
              return
            }
          }
        }
        eventBuffer.finish()
      } catch {
        commandStream.finish()
        eventBuffer.finish(throwing: error)
      }
    }
    self.rpcTask = rpcTask
    rpcTaskControl.install(rpcTask)
    eventBuffer.onTermination { termination in
      commandStream.finish()
      if case .cancelled = termination {
        rpcTask.cancel()
      }
    }
  }

  deinit {
    self.commandStream.finish()
    self.rpcTask.cancel()
  }

  func submit(requestID: String, text: String) async throws {
    try GRPCHuskyChatClient<Transport>.validateIdentifier(requestID)
    let bytes = text.utf8.count
    guard bytes <= Int(self.maximumMessageBytes) else {
      throw HuskyClientError.messageTooLarge(
        actualUTF8Bytes: bytes,
        maximum: self.maximumMessageBytes
      )
    }
    var submit = HuskySubmitMessage()
    submit.requestID = requestID
    submit.conversationID = self.conversationID
    submit.text = text
    var command = HuskyClientCommand()
    command.command = .submitMessage(submit)
    try self.send(command)
  }

  func cancel(requestID: String) async throws {
    try GRPCHuskyChatClient<Transport>.validateIdentifier(requestID)
    var cancel = HuskyCancelRequest()
    cancel.requestID = requestID
    var command = HuskyClientCommand()
    command.command = .cancelRequest(cancel)
    try self.send(command)
  }

  func end() async {
    var command = HuskyClientCommand()
    command.command = .endSession(HuskyEndSession())
    if self.commandStream.yield(command) == .overflow {
      self.abort(error: HuskyClientError.resynchronizationRequired)
    }
    self.commandStream.finish()
    await self.rpcTask.value
  }

  private func send(_ command: HuskyClientCommand) throws {
    switch self.commandStream.yield(command) {
    case .enqueued: return
    case .overflow:
      self.abort(error: HuskyClientError.resynchronizationRequired)
      throw HuskyClientError.resynchronizationRequired
    case .terminated: throw HuskyClientError.resynchronizationRequired
    @unknown default: throw HuskyClientError.resynchronizationRequired
    }
  }

  private func abort(error: any Error) {
    self.commandStream.finish()
    self.eventBuffer.finish(throwing: error)
    self.rpcTaskControl.cancel()
  }
}

private final class HuskyTaskCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<Void, Never>?
  private var isCancelled = false

  func install(_ task: Task<Void, Never>) {
    self.lock.lock()
    self.task = task
    let isCancelled = self.isCancelled
    self.lock.unlock()
    if isCancelled {
      task.cancel()
    }
  }

  func cancel() {
    self.lock.lock()
    self.isCancelled = true
    let task = self.task
    self.lock.unlock()
    task?.cancel()
  }
}
