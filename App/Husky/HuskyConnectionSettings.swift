import HuskyCore
import SwiftUI

struct HuskyConnectionSettings: View {
  let client: HuskyLiveChatClient
  @Environment(\.dismiss) private var dismiss
  @State private var editingID: UUID?
  @State private var name = ""
  @State private var endpoint = "https://"
  @State private var token = ""
  @State private var replaceToken = false
  @State private var loopback = false
  @State private var errorText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Connections").font(.title2)
      Picker("Saved connection", selection: $editingID) {
        Text("New connection").tag(nil as UUID?)
        ForEach(client.profiles.profiles) { profile in
          Text(profile.name).tag(Optional(profile.id))
        }
      }
      .onChange(of: editingID) { _, id in load(id) }
      Form {
        TextField("Name", text: $name)
        TextField("Endpoint", text: $endpoint)
          .help("Use https://host:port. HTTP is allowed only for explicit loopback development.")
        Toggle("Allow local HTTP development connection", isOn: $loopback)
        Toggle("Replace saved token", isOn: $replaceToken)
        if replaceToken {
          SecureField("Bearer token (empty removes it)", text: $token)
        }
      }
      Text("Tokens are stored in Keychain. Message drafts are saved locally on this Mac.")
        .font(.caption).foregroundStyle(.secondary)
      if let errorText { Text(errorText).font(.callout).foregroundStyle(.red) }
      HStack {
        if let editingID {
          Button("Delete", role: .destructive) {
            Task {
              if client.profiles.selectedProfileID == editingID { await client.selectProfile(nil) }
              do {
                try client.profiles.delete(id: editingID)
                self.editingID = nil
                load(nil)
              } catch { errorText = "The connection could not be deleted. Please try again." }
            }
          }
        }
        Spacer()
        Button("Cancel") {
          token = ""
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Button("Save and Connect") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 440)
    .onDisappear { token = "" }
  }

  private func load(_ id: UUID?) {
    let profile = client.profiles.profiles.first { $0.id == id }
    name = profile?.name ?? ""
    endpoint = profile?.endpoint ?? "https://"
    loopback = profile?.allowsInsecureLoopback ?? false
    token = ""
    replaceToken = false
    errorText = nil
  }

  private func save() {
    let id = editingID ?? UUID()
    do {
      let profile = HuskyBackendProfile(
        id: id, name: name, endpoint: endpoint, allowsInsecureLoopback: loopback)
      try client.profiles.save(profile, token: replaceToken ? token : nil)
      token = ""
      Task { await client.selectProfile(id) }
      dismiss()
    } catch {
      token = ""
      errorText =
        "Could not save. Use an HTTPS endpoint without a path or credentials, or enable HTTP for a literal loopback address. Check Keychain access if the endpoint is valid."
    }
  }
}
