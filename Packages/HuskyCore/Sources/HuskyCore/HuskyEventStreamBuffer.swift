import Foundation

struct HuskyEventStreamBuffer: Sendable {
  enum YieldResult: Sendable, Equatable {
    case buffered
    case overflow
    case terminated
  }

  let stream: AsyncThrowingStream<HuskySequencedEvent, any Error>
  private let continuation: AsyncThrowingStream<HuskySequencedEvent, any Error>.Continuation

  init(capacity: Int) {
    precondition(capacity > 0)
    let pair = AsyncThrowingStream<HuskySequencedEvent, any Error>.makeStream(
      of: HuskySequencedEvent.self,
      bufferingPolicy: .bufferingOldest(capacity)
    )
    self.stream = pair.stream
    self.continuation = pair.continuation
  }

  func yield(_ event: HuskySequencedEvent) -> YieldResult {
    switch self.continuation.yield(event) {
    case .enqueued:
      return .buffered
    case .dropped:
      // The dropped event stays recoverable from the acknowledged cursor.
      // Finish with an explicit error so consumers reconnect instead of
      // silently continuing with a hole in the event log.
      self.continuation.finish(throwing: HuskyClientError.eventBufferOverflow)
      return .overflow
    case .terminated:
      return .terminated
    @unknown default:
      self.continuation.finish(throwing: HuskyClientError.eventBufferOverflow)
      return .overflow
    }
  }

  func finish(throwing error: (any Error)? = nil) {
    if let error {
      self.continuation.finish(throwing: error)
    } else {
      self.continuation.finish()
    }
  }

  func onTermination(
    _ handler:
      @escaping @Sendable (
        AsyncThrowingStream<HuskySequencedEvent, any Error>.Continuation.Termination
      ) -> Void
  ) {
    self.continuation.onTermination = handler
  }
}
