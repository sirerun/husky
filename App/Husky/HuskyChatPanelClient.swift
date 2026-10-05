import Foundation

/// Presentation data owned by the backend-facing core and adapted at the app boundary.
struct HuskyPanelMessage: Identifiable, Sendable, Equatable {
  enum Role: Sendable, Equatable {
    case user
    case backend
  }

  let id: String
  let role: Role
  let text: String
}

/// Injected seam for the panel. The app target supplies an adapter around
/// HuskyCore; this UI target deliberately contains no transport implementation.
@MainActor
protocol HuskyChatPanelClient: AnyObject {
  func messageUpdates() -> AsyncStream<[HuskyPanelMessage]>
  func submit(_ text: String) async throws
}
