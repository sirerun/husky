import Foundation

/// Controls deterministic behavior for the local Husky protocol fixture.
public struct HuskyFixtureConfiguration: Sendable {
  /// The number of sequenced conversation events retained for stream replay.
  public var retainedEventLimit: Int

  /// Delay between scripted response steps. Tests can set this to zero.
  public var responseStepDelay: Duration

  /// Emits one server-originated assistant message after each conversation's
  /// first successful session attach.
  public var emitUnsolicitedMessageOnFirstAttach: Bool

  public init(
    retainedEventLimit: Int = 256,
    responseStepDelay: Duration = .milliseconds(20),
    emitUnsolicitedMessageOnFirstAttach: Bool = false
  ) {
    self.retainedEventLimit = max(1, retainedEventLimit)
    self.responseStepDelay = responseStepDelay
    self.emitUnsolicitedMessageOnFirstAttach = emitUnsolicitedMessageOnFirstAttach
  }
}
