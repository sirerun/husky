import SwiftUI

struct HuskyChatPanelView: View {
  @State private var model: HuskyChatPanelModel
  private let isDemo: Bool
  @State private var draft = ""
  @State private var materialCandidate: HuskyMaterialCandidate = .hudWindow
  @State private var showsFullHistory = false
  @State private var isAtBottom = true

  @ScaledMetric(relativeTo: .body) private var messageFontSize: CGFloat = 18

  init(model: HuskyChatPanelModel, isDemo: Bool = false) {
    _model = State(initialValue: model)
    self.isDemo = isDemo
  }

  var body: some View {
    VStack(spacing: 12) {
      header
      transcript
      composer
      if let statusText = model.statusText {
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(18)
    .frame(width: 560)
    .background(Color.clear)
    .preferredColorScheme(nil)
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Husky")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
        .gesture(WindowDragGesture())

      if isDemo {
        Text("DEMO FIXTURE")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Color.secondary.opacity(0.12), in: Capsule())
          .accessibilityLabel("Demo fixture")
      }

      Spacer(minLength: 8)

      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          showsFullHistory.toggle()
        }
      } label: {
        Image(systemName: showsFullHistory ? "arrow.down.to.line" : "clock.arrow.circlepath")
          .frame(width: 32, height: 32)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(
        showsFullHistory ? "Restore the soft history fade" : "Show full history without the fade"
      )
      .accessibilityLabel(showsFullHistory ? "Restore soft history fade" : "Show full history")

      Menu {
        ForEach(HuskyMaterialCandidate.allCases) { candidate in
          Button {
            materialCandidate = candidate
          } label: {
            if candidate == materialCandidate {
              Label(candidate.title, systemImage: "checkmark")
            } else {
              Text(candidate.title)
            }
          }
        }
      } label: {
        Image(systemName: "circle.lefthalf.filled")
          .frame(width: 32, height: 32)
          .contentShape(Circle())
      }
      .menuStyle(.borderlessButton)
      .help("Compare native backdrop materials and a custom tint")
      .accessibilityLabel("Choose chat surface appearance")
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 4)
  }

  private var transcript: some View {
    GeometryReader { viewport in
      ScrollViewReader { scrollProxy in
        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 18) {
            if model.messages.isEmpty {
              Text("Messages from your backend will appear here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            } else {
              ForEach(model.messages) { message in
                HuskyMessageBubble(
                  message: message,
                  materialCandidate: materialCandidate,
                  fontSize: messageFontSize
                )
                .id(message.id)
              }
            }
            Color.clear
              .frame(height: 1)
              .id(HuskyChatPanelView.bottomAnchor)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 10)
          .background {
            GeometryReader { content in
              Color.clear.preference(
                key: HuskyTranscriptHeightKey.self,
                value: content.frame(in: .named("HuskyTranscript")).maxY
              )
            }
          }
        }
        .coordinateSpace(name: "HuskyTranscript")
        .scrollIndicators(.hidden)
        .frame(height: min(510, max(220, viewport.size.height)))
        .mask {
          if showsFullHistory {
            Rectangle()
          } else {
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.12), location: 0.12),
                .init(color: .black, location: 0.30),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          }
        }
        .overlay(alignment: .top) {
          if !showsFullHistory {
            LinearGradient(
              colors: [Color(nsColor: .windowBackgroundColor).opacity(0.12), .clear],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: 110)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
          }
        }
        .onPreferenceChange(HuskyTranscriptHeightKey.self) { contentBottom in
          isAtBottom = contentBottom <= viewport.size.height + 20
        }
        .onChange(of: model.messages.count) { _, _ in
          guard isAtBottom else { return }
          withAnimation(.easeOut(duration: 0.18)) {
            scrollProxy.scrollTo(HuskyChatPanelView.bottomAnchor, anchor: .bottom)
          }
        }
        .onAppear {
          scrollProxy.scrollTo(HuskyChatPanelView.bottomAnchor, anchor: .bottom)
        }
        .accessibilityLabel("Conversation history")
      }
    }
    .frame(maxHeight: 510)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Message", text: $draft, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.body)
        .lineLimit(1...5)
        .padding(.vertical, 10)
        .accessibilityLabel("Message")
        .onSubmit(sendDraft)

      Button(action: sendDraft) {
        Image(systemName: "arrow.up")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(Color.accentColor, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
      .accessibilityLabel("Send message")
      .accessibilityHint("Sends this typed message to the selected backend")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background {
      HuskyMaterialSurface(candidate: materialCandidate, cornerRadius: 26)
        .overlay {
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(customTint.opacity(materialCandidate == .customTint ? 0.68 : 0.13))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
  }

  private var customTint: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  private func sendDraft() {
    let text = draft
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    Task {
      if await model.submit(text) {
        draft = ""
      }
    }
  }

  private static let bottomAnchor = "husky-transcript-bottom"
}

private struct HuskyMessageBubble: View {
  let message: HuskyPanelMessage
  let materialCandidate: HuskyMaterialCandidate
  let fontSize: CGFloat

  var body: some View {
    HStack {
      if message.role == .backend { Spacer(minLength: 38) }

      Text(message.text)
        .font(.system(size: fontSize))
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 560 * 0.87, alignment: .leading)
        .background {
          HuskyMaterialSurface(candidate: materialCandidate, cornerRadius: 26)
            .overlay {
              RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                  Color(nsColor: .controlBackgroundColor).opacity(
                    materialCandidate == .customTint ? 0.68 : 0.13))
            }
            .overlay {
              RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Backend"): \(message.text)")

      if message.role == .user { Spacer(minLength: 38) }
    }
  }
}

private struct HuskyTranscriptHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

#Preview("Static appearance sample — no backend") {
  let previewClient = HuskyPreviewChatClient()
  HuskyChatPanelView(model: HuskyChatPanelModel(client: previewClient), isDemo: true)
    .frame(height: 660)
}

@MainActor
private final class HuskyPreviewChatClient: HuskyChatPanelClient {
  func messageUpdates() -> AsyncStream<[HuskyPanelMessage]> {
    AsyncStream { continuation in
      continuation.yield([
        HuskyPanelMessage(
          id: "preview-user", role: .user,
          text: "Can we keep the latest notes in view while I read the earlier messages?"),
        HuskyPanelMessage(
          id: "preview-backend", role: .backend,
          text:
            "Yes. New events follow the latest message only while the history view is already at the bottom."
        ),
      ])
      continuation.finish()
    }
  }

  func statusUpdates() -> AsyncStream<String?> {
    AsyncStream { continuation in
      continuation.yield(nil)
      continuation.finish()
    }
  }

  func submit(_ text: String) async throws {}

  func shutdown() async {}
}
