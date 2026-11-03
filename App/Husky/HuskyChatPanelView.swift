import HuskyCore
import HuskyWindowing
import SwiftUI

struct HuskyChatPanelView: View {
  @State private var model: HuskyChatPanelModel
  private let isDemo: Bool
  @State private var localDraft = ""
  @State private var showsControls = false
  @State private var showsSettings = false
  @State private var showsRecovery = false
  @State private var recoveryResult: String?
  @State private var newConversationTitle = ""
  @State private var showsCreateConversation = false
  private var draft: String { model.liveClient?.draft.text ?? localDraft }
  private var draftBinding: Binding<String> {
    Binding(
      get: { draft },
      set: { value in
        if let live = model.liveClient { live.editDraft(value) } else { localDraft = value }
      })
  }
  @State private var materialCandidate: HuskyMaterialCandidate = .hudWindow
  @State private var showsFullHistory = false
  @State private var isAtBottom = true
  @State private var olderHistoryAnchor: String?
  @State private var historyLoadRevision = 0

  @ScaledMetric(relativeTo: .body) private var messageFontSize: CGFloat = 18

  init(model: HuskyChatPanelModel, isDemo: Bool = false) {
    _model = State(initialValue: model)
    self.isDemo = isDemo
  }

  var body: some View {
    VStack(spacing: 12) {
      transcript
      composer
    }
    .padding(18)
    .frame(width: HuskyPanelLayout.width, height: HuskyPanelLayout.height)
    .background(Color.clear)
    .preferredColorScheme(nil)
    .onReceive(NotificationCenter.default.publisher(for: .huskyShowChatControls)) { _ in
      showsControls = true
    }
    .contextMenu {
      Button("Chat controls…") { showsControls = true }
    }
    .sheet(isPresented: $showsControls) {
      controls
    }
  }

  @ViewBuilder private func clientControls(_ live: HuskyLiveChatClient) -> some View {
    HStack(spacing: 8) {
      Menu {
        ForEach(live.profiles.profiles) { profile in
          Button(profile.name) { Task { await live.selectProfile(profile.id) } }
        }
        Divider()
        Button("Connection settings…") {
          showsSettings = true
        }
      } label: {
        Label(
          live.profiles.profiles.first { $0.id == live.profiles.selectedProfileID }?.name
            ?? "Connect", systemImage: "network"
        )
        .lineLimit(1)
      }
      Menu {
        ForEach(live.conversation.conversations) { conversation in
          Button(conversation.title.isEmpty ? "Untitled" : conversation.title) {
            Task { await live.selectConversation(conversation.id) }
          }
        }
        if live.conversation.hasMoreConversations {
          Button("Load more conversations") {
            Task { await live.conversation.loadMoreConversations() }
          }
        }
        Divider()
        Button("New conversation…") {
          showsCreateConversation = true
        }
      } label: {
        Text(
          live.conversation.conversations.first {
            $0.id == live.conversation.selectedConversationID
          }?.title ?? "Conversations"
        )
        .lineLimit(1)
      }
      .disabled(live.profiles.selectedProfileID == nil)
      Button {
        Task { await live.selectProfile(live.profiles.selectedProfileID) }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .help("Reconnect")
      .accessibilityLabel("Reconnect to backend")
      if live.conversation.activeRequestID != nil {
        Button("Cancel") { Task { await live.conversation.cancelActiveRequest() } }
      }
    }
    .font(.caption)
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Chat controls").font(.headline)
      if isDemo { Text("Demo fixture").foregroundStyle(.secondary) }
      if let live = model.liveClient { clientControls(live) }
      if model.recoveryClient != nil {
        Button("Recover connection settings…") {
          showsRecovery = true
        }
        if let recoveryResult { Text(recoveryResult).font(.caption) }
      }
      if let live = model.liveClient, live.conversation.hasMoreHistory {
        Button("Load older messages") {
          isAtBottom = false
          let anchor = model.messages.first?.id
          Task {
            await live.conversation.loadOlderMessages()
            olderHistoryAnchor = anchor
            historyLoadRevision += 1
          }
        }
        .disabled(live.conversation.isLoadingHistory)
      }
      Toggle("Show full history without the fade", isOn: $showsFullHistory)
      Picker("Surface appearance", selection: $materialCandidate) {
        ForEach(HuskyMaterialCandidate.allCases) { candidate in
          Text(candidate.title).tag(candidate)
        }
      }
      if let statusText = model.statusText {
        Text(statusText).font(.caption).foregroundStyle(.secondary)
      }
      Button("Done") { showsControls = false }
        .keyboardShortcut(.cancelAction)
    }
    .padding(24)
    .frame(minWidth: 360)
    .alert("Reset local connection settings?", isPresented: $showsRecovery) {
      Button("Preserve Backup and Reset", role: .destructive) {
        do {
          try model.recoveryClient?.recoverSettings()
          recoveryResult = "A backup was preserved. Quit and reopen Husky to configure connections."
        } catch {
          recoveryResult = "Recovery failed. Your existing settings have been retained."
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The existing settings and drafts will be kept in a local preferences backup. Saved Keychain tokens will remain untouched. Restart Husky after recovery."
      )
    }
    .sheet(isPresented: $showsSettings) {
      if let live = model.liveClient { HuskyConnectionSettings(client: live) }
    }
    .alert("New conversation", isPresented: $showsCreateConversation) {
      TextField("Title", text: $newConversationTitle)
      Button("Create") {
        let title = newConversationTitle
        newConversationTitle = ""
        Task { await model.liveClient?.createConversation(title: title) }
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var transcript: some View {
    GeometryReader { viewport in
      ScrollViewReader { scrollProxy in
        ScrollView(.vertical) {
          LazyVStack(alignment: .leading, spacing: 18 * HuskyPanelLayout.sizeScale) {
            ForEach(model.messages) { message in
              HuskyMessageBubble(
                message: message,
                materialCandidate: materialCandidate,
                fontSize: messageFontSize
              )
              .id(message.id)
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
        .frame(
          height: min(
            HuskyPanelLayout.transcriptMaximumHeight,
            max(HuskyPanelLayout.transcriptMinimumHeight, viewport.size.height))
        )
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
        .onChange(of: historyLoadRevision) { _, _ in
          if let anchor = olderHistoryAnchor { scrollProxy.scrollTo(anchor, anchor: .top) }
        }
        .onPreferenceChange(HuskyTranscriptHeightKey.self) { contentBottom in
          isAtBottom = contentBottom <= viewport.size.height + 20
        }
        .onChange(of: model.messages) { _, _ in
          guard isAtBottom else { return }
          withAnimation(.easeOut(duration: 0.18)) {
            scrollProxy.scrollTo(HuskyChatPanelView.bottomAnchor, anchor: .bottom)
          }
        }
        .onChange(of: model.liveClient?.conversation.selectedConversationID) { _, _ in
          isAtBottom = true
          scrollProxy.scrollTo(HuskyChatPanelView.bottomAnchor, anchor: .bottom)
        }
        .onAppear {
          scrollProxy.scrollTo(HuskyChatPanelView.bottomAnchor, anchor: .bottom)
        }
        .accessibilityLabel("Conversation history")
      }
    }
    .frame(maxHeight: HuskyPanelLayout.transcriptMaximumHeight)
  }

  private var canSend: Bool {
    model.canSubmit && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Message", text: draftBinding, axis: .vertical)
        .disabled(
          model.liveClient?.draft.pendingRequestID != nil
            || model.recoveryClient != nil
            || (model.liveClient != nil
              && model.liveClient?.conversation.selectedConversationID == nil)
        )
        .textFieldStyle(.plain)
        .font(.body)
        .lineLimit(1...5)
        .padding(.vertical, 10)
        .accessibilityLabel("Message")
        .accessibilityHint(model.statusText ?? "Type a message to the selected backend")
        .onSubmit(sendDraft)

      Button(action: sendDraft) {
        Image(systemName: "arrow.up")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(model.isConnected ? Color.accentColor : Color.gray, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(!canSend)
      .accessibilityLabel(
        model.liveClient?.draft.pendingRequestID == nil ? "Send message" : "Retry pending message"
      )
      .accessibilityHint("Sends this typed message to the selected backend")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background {
      HuskyMaterialSurface(
        candidate: materialCandidate, cornerRadius: 1_000
      )
      .overlay {
        Capsule()
          .fill(customTint.opacity(materialCandidate == .customTint ? 0.68 : 0.13))
      }
      .overlay {
        Capsule()
          .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
      }
    }
    .clipShape(Capsule())
  }

  private var customTint: Color {
    Color(nsColor: .controlBackgroundColor)
  }

  private func sendDraft() {
    let text = draft
    guard canSend else { return }
    Task {
      if await model.submit(text) {
        if model.liveClient == nil { localDraft = "" }
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
        .padding(.horizontal, HuskyPanelLayout.messageHorizontalPadding)
        .padding(.vertical, HuskyPanelLayout.messageVerticalPadding)
        .frame(maxWidth: HuskyPanelLayout.messageMaximumWidth, alignment: .leading)
        .background {
          HuskyMaterialSurface(
            candidate: materialCandidate, cornerRadius: HuskyPanelLayout.messageCornerRadius
          )
          .overlay {
            RoundedRectangle(cornerRadius: HuskyPanelLayout.messageCornerRadius, style: .continuous)
              .fill(
                Color(nsColor: .controlBackgroundColor).opacity(
                  materialCandidate == .customTint ? 0.68 : 0.13))
          }
          .overlay {
            RoundedRectangle(cornerRadius: HuskyPanelLayout.messageCornerRadius, style: .continuous)
              .fill(Color.accentColor.opacity(message.role == .user ? 0.08 : 0))
          }
          .overlay {
            RoundedRectangle(cornerRadius: HuskyPanelLayout.messageCornerRadius, style: .continuous)
              .strokeBorder(
                message.role == .user
                  ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.15),
                lineWidth: 1)
          }
        }
        .clipShape(
          RoundedRectangle(cornerRadius: HuskyPanelLayout.messageCornerRadius, style: .continuous)
        )
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
    .frame(width: HuskyPanelLayout.width, height: HuskyPanelLayout.height)
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
