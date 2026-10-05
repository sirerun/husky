import Foundation
import GRPCCore
import HuskyProtocol

/// Implements the frozen husky.v1 API with an in-memory deterministic script.
public struct HuskyFixtureService: HuskyHuskyBackend.SimpleServiceProtocol {
  private let store: HuskyFixtureStore

  public init(store: HuskyFixtureStore = .init()) {
    self.store = store
  }

  public func getCapabilities(
    request: HuskyGetCapabilitiesRequest,
    context: ServerContext
  ) async throws -> HuskyGetCapabilitiesResponse {
    await store.capabilities()
  }

  public func listConversations(
    request: HuskyListConversationsRequest,
    context: ServerContext
  ) async throws -> HuskyListConversationsResponse {
    try await store.listConversations(request)
  }

  public func createConversation(
    request: HuskyCreateConversationRequest,
    context: ServerContext
  ) async throws -> HuskyCreateConversationResponse {
    try await store.createConversation(request)
  }

  public func getHistory(
    request: HuskyGetHistoryRequest,
    context: ServerContext
  ) async throws -> HuskyGetHistoryResponse {
    try await store.history(request)
  }

  public func conversationSession(
    request: RPCAsyncSequence<HuskyClientCommand, any Error>,
    response: RPCWriter<HuskyBackendEvent>,
    context: ServerContext
  ) async throws {
    var requests = request.makeAsyncIterator()
    guard let first = try await requests.next(), case .startSession(let start) = first.command
    else {
      throw RPCError(
        code: .invalidArgument, message: "StartSession must be the first fixture stream command.")
    }

    let conversationID = start.conversationID
    let subscriptionID = UUID()
    let (events, continuation) = AsyncStream.makeStream(of: HuskyBackendEvent.self)
    continuation.onTermination = { [store] _ in
      Task { await store.detach(conversationID: conversationID, subscriptionID: subscriptionID) }
    }
    let requiresResync = try await store.attach(
      conversationID: conversationID,
      afterSequence: start.afterSequence,
      subscriptionID: subscriptionID,
      continuation: continuation
    )

    let writer = Task {
      for await event in events {
        try await response.write(event)
      }
    }

    do {
      if requiresResync {
        continuation.finish()
        try await writer.value
        return
      }

      while let command = try await requests.next() {
        switch command.command {
        case .startSession:
          throw RPCError(
            code: .invalidArgument,
            message: "StartSession can only appear as the first fixture stream command.")
        case .submitMessage(let submission):
          let accepted = try await store.submit(submission, in: conversationID)
          // New submissions are already published by the event log. Only the
          // sequence-zero idempotency acknowledgement needs direct delivery.
          if accepted.sequence == 0 { continuation.yield(accepted) }
        case .cancelRequest(let cancellation):
          let cancelled = try await store.cancel(
            requestID: cancellation.requestID, in: conversationID)
          if cancelled.sequence == 0 { continuation.yield(cancelled) }
        case .endSession:
          continuation.finish()
          try await writer.value
          await store.detach(conversationID: conversationID, subscriptionID: subscriptionID)
          return
        case .none:
          throw RPCError(
            code: .invalidArgument, message: "A fixture stream command must select one command.")
        }
      }
      // A transport close disconnects the listener without cancelling accepted
      // generation tasks. Those tasks continue to append canonical history.
      continuation.finish()
      try await writer.value
    } catch {
      continuation.finish()
      await store.detach(conversationID: conversationID, subscriptionID: subscriptionID)
      throw error
    }
    await store.detach(conversationID: conversationID, subscriptionID: subscriptionID)
  }
}
