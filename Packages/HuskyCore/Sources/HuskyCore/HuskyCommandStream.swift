import Foundation
import HuskyProtocol

struct HuskyCommandStream: Sendable {
  enum YieldResult: Sendable, Equatable {
    case enqueued
    case overflow
    case terminated
  }

  let stream: AsyncStream<HuskyClientCommand>
  private let continuation: AsyncStream<HuskyClientCommand>.Continuation

  init(capacity: Int) {
    precondition(capacity > 0)
    let pair = AsyncStream<HuskyClientCommand>.makeStream(
      of: HuskyClientCommand.self,
      bufferingPolicy: .bufferingOldest(capacity)
    )
    self.stream = pair.stream
    self.continuation = pair.continuation
  }

  func yield(_ command: HuskyClientCommand) -> YieldResult {
    switch self.continuation.yield(command) {
    case .enqueued:
      return .enqueued
    case .dropped:
      self.continuation.finish()
      return .overflow
    case .terminated:
      return .terminated
    @unknown default:
      self.continuation.finish()
      return .overflow
    }
  }

  func finish() {
    self.continuation.finish()
  }
}
