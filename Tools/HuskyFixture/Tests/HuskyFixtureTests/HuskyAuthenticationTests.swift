import GRPCCore
import GRPCInProcessTransport
import HuskyCore
import HuskyFixture
import HuskyProtocol
import XCTest

final class HuskyAuthenticationTests: XCTestCase, @unchecked Sendable {
  func testAuthorizationReachesEveryUnaryAndStreamingMethod() async throws {
    let transport = InProcessTransport()
    let recorder = AuthMethodRecorder()
    let server = GRPCServer(
      transport: transport.server,
      services: [HuskyFixtureService(store: HuskyFixtureStore())],
      interceptors: [RequiredToken(recorder: recorder)])
    let task = Task { try await server.serve() }
    defer { task.cancel() }
    try await withGRPCClient(transport: transport.client) { client in
      let backend = HuskyHuskyBackend.Client(wrapping: client)
      let unauthenticated = GRPCHuskyChatClient(backend: backend)
      do {
        _ = try await unauthenticated.getCapabilities()
        XCTFail("Missing authorization must fail")
      } catch let error as RPCError {
        XCTAssertEqual(error.code, .unauthenticated)
      }
      let api = GRPCHuskyChatClient(
        backend: backend, metadata: ["authorization": "Bearer fixture-test"])
      _ = try await api.getCapabilities()
      let conversation = try await api.createConversation(
        requestID: "auth-create", title: "Authorization")
      _ = try await api.listConversations(pageSize: 10, before: nil)
      _ = try await api.getHistory(conversationID: conversation.id, pageSize: 10, before: nil)
      let session = try await api.openConversation(
        conversationID: conversation.id, afterSequence: 0, resumeToken: nil)
      for try await event in session.events {
        if case .sessionReady = event.event { break }
      }
      await session.end()
    }
    let methods = await recorder.snapshot()
    XCTAssertEqual(
      methods,
      Set([
        "GetCapabilities", "ListConversations", "CreateConversation", "GetHistory",
        "ConversationSession",
      ]))
  }
}

private actor AuthMethodRecorder {
  var methods: Set<String> = []
  func record(_ method: String) { methods.insert(method) }
  func snapshot() -> Set<String> { methods }
}

private struct RequiredToken: ServerInterceptor {
  let recorder: AuthMethodRecorder
  func intercept<Input: Sendable, Output: Sendable>(
    request: StreamingServerRequest<Input>, context: ServerContext,
    next:
      @Sendable (StreamingServerRequest<Input>, ServerContext) async throws ->
      StreamingServerResponse<Output>
  ) async throws -> StreamingServerResponse<Output> {
    guard
      request.metadata[stringValues: "authorization"].first(where: { _ in true })
        == "Bearer fixture-test"
    else {
      throw RPCError(code: .unauthenticated, message: "Authorization required")
    }
    await recorder.record(context.descriptor.method)
    return try await next(request, context)
  }
}
