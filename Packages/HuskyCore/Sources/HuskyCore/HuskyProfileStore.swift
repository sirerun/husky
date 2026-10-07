import CoreFoundation
import Foundation
import Observation
import Security

public struct HuskyEndpoint: Sendable, Equatable {
  public let host: String
  public let port: Int
  public let usesTLS: Bool

  public init(host: String, port: Int, usesTLS: Bool) {
    self.host = host
    self.port = port
    self.usesTLS = usesTLS
  }
}

public struct HuskyBackendProfile: Codable, Sendable, Equatable, Identifiable {
  public let id: UUID
  public let name: String
  public let endpoint: String
  public let allowsInsecureLoopback: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    endpoint: String,
    allowsInsecureLoopback: Bool = false
  ) {
    self.id = id
    self.name = name
    self.endpoint = endpoint
    self.allowsInsecureLoopback = allowsInsecureLoopback
  }

  public func validatedEndpoint() throws -> HuskyEndpoint {
    let trimmedName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty, self.name.utf8.count <= 256 else {
      throw HuskyProfileStoreError.invalidProfileName
    }
    guard self.endpoint == self.endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
      let components = URLComponents(string: self.endpoint),
      components.url != nil,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.percentEncodedPath.isEmpty,
      let scheme = components.scheme?.lowercased(),
      let host = components.host,
      !host.isEmpty,
      !host.contains("%")
    else {
      throw HuskyProfileStoreError.invalidEndpoint
    }

    let usesTLS: Bool
    let defaultPort: Int
    switch scheme {
    case "https":
      usesTLS = true
      defaultPort = 443
    case "http":
      guard self.allowsInsecureLoopback, Self.isLiteralLoopback(host) else {
        throw HuskyProfileStoreError.insecureEndpointNotAllowed
      }
      usesTLS = false
      defaultPort = 80
    default:
      throw HuskyProfileStoreError.invalidEndpoint
    }

    let port = components.port ?? defaultPort
    guard (1...65_535).contains(port) else {
      throw HuskyProfileStoreError.invalidEndpoint
    }
    return HuskyEndpoint(host: Self.unwrappedHost(host), port: port, usesTLS: usesTLS)
  }

  private static func unwrappedHost(_ host: String) -> String {
    if host.hasPrefix("["), host.hasSuffix("]") {
      return String(host.dropFirst().dropLast())
    }
    return host
  }

  private static func isLiteralLoopback(_ host: String) -> Bool {
    let unwrappedHost = Self.unwrappedHost(host)

    if unwrappedHost == "::1" { return true }

    let octets = unwrappedHost.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4 else { return false }
    var values: [UInt8] = []
    for octet in octets {
      guard let value = UInt8(String(octet)), String(value) == String(octet) else {
        return false
      }
      values.append(value)
    }
    return values[0] == 127
  }
}

public struct HuskyDraftRecord: Codable, Sendable, Equatable {
  public let text: String
  public let pendingRequestID: String?
  public let pendingText: String?

  public init(text: String, pendingRequestID: String? = nil, pendingText: String? = nil) {
    self.text = text
    self.pendingRequestID = pendingRequestID
    self.pendingText = pendingText
  }
}

public protocol HuskyCredentialStore: Sendable {
  func read(profileID: UUID) throws -> String?
  func write(_ token: String, profileID: UUID) throws
  func delete(profileID: UUID) throws
}

public struct HuskyKeychainCredentialStore: HuskyCredentialStore {
  public static let service = "com.sirerun.husky.backend-token"

  public init() {}

  public func read(profileID: UUID) throws -> String? {
    var query = Self.baseQuery(profileID: profileID)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw HuskyProfileStoreError.credentialOperationFailed(
        operation: "read", status: status)
    }
    guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
      throw HuskyProfileStoreError.credentialDataInvalid
    }
    return token
  }

  public func write(_ token: String, profileID: UUID) throws {
    let data = Data(token.utf8)
    let query = Self.baseQuery(profileID: profileID)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw HuskyProfileStoreError.credentialOperationFailed(
        operation: "write", status: updateStatus)
    }

    var addQuery = query
    for (key, value) in attributes {
      addQuery[key] = value
    }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess { return }
    if addStatus == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if retryStatus == errSecSuccess { return }
      throw HuskyProfileStoreError.credentialOperationFailed(
        operation: "write", status: retryStatus)
    }
    throw HuskyProfileStoreError.credentialOperationFailed(operation: "write", status: addStatus)
  }

  public func delete(profileID: UUID) throws {
    let status = SecItemDelete(Self.baseQuery(profileID: profileID) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw HuskyProfileStoreError.credentialOperationFailed(
        operation: "delete", status: status)
    }
  }

  private static func baseQuery(profileID: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: profileID.uuidString,
    ]
  }
}

public enum HuskyProfileStoreError: Error, Sendable, Equatable, LocalizedError {
  case invalidProfileName
  case invalidEndpoint
  case insecureEndpointNotAllowed
  case duplicateProfileID
  case profileNotFound
  case invalidSelection
  case invalidConversationID
  case invalidDraft
  case invalidPreferences
  case unsupportedPreferencesVersion(Int)
  case preferencesWriteFailed
  case noPreferencesToRecover
  case recoveryBackupUnavailable
  case recoveryBackupVerificationFailed
  case recoveryPreferencesChanged
  case recoveryRemovalFailed
  case credentialOperationFailed(operation: String, status: Int32)
  case credentialDataInvalid
  case transactionRollbackFailed

  public var errorDescription: String? {
    switch self {
    case .invalidProfileName: "Enter a profile name containing non-space text."
    case .invalidEndpoint: "Enter a valid HTTPS endpoint URL without a path or credentials."
    case .insecureEndpointNotAllowed:
      "Plain HTTP is allowed only for an explicitly enabled literal loopback endpoint."
    case .duplicateProfileID: "A profile with this identifier already exists."
    case .profileNotFound: "The selected backend profile no longer exists."
    case .invalidSelection: "Select a saved backend profile."
    case .invalidConversationID: "The conversation identifier is invalid."
    case .invalidDraft: "The draft or pending message state is invalid."
    case .invalidPreferences: "Saved Husky preferences could not be read."
    case .unsupportedPreferencesVersion(let version):
      "Saved Husky preferences use an unsupported version (\(version))."
    case .preferencesWriteFailed: "Husky preferences could not be saved."
    case .noPreferencesToRecover: "No saved Husky preferences were found to recover."
    case .recoveryBackupUnavailable: "A unique Husky recovery backup could not be created."
    case .recoveryBackupVerificationFailed:
      "The Husky recovery backup could not be verified; the original preferences remain."
    case .recoveryPreferencesChanged:
      "Husky preferences changed during recovery; the current preferences were preserved."
    case .recoveryRemovalFailed:
      "Husky could not remove the active preferences; saved data was preserved."
    case .credentialOperationFailed(let operation, let status):
      "The backend credential could not be \(operation) (Keychain status \(status))."
    case .credentialDataInvalid: "The saved backend credential could not be read."
    case .transactionRollbackFailed:
      "A storage update failed and its credential rollback could not be completed."
    }
  }
}

@MainActor
protocol HuskyProfilePreferencesBacking: AnyObject {
  func load() -> Data?
  func save(_ data: Data?) throws
}

@MainActor
private final class UserDefaultsHuskyProfilePreferences: HuskyProfilePreferencesBacking {
  private let defaults: UserDefaults
  private let key = "com.sirerun.husky.profile-store.v1"

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func load() -> Data? {
    self.defaults.data(forKey: self.key)
  }

  func save(_ data: Data?) throws {
    if let data {
      self.defaults.set(data, forKey: self.key)
    } else {
      self.defaults.removeObject(forKey: self.key)
    }
    guard self.defaults.data(forKey: self.key) == data else {
      throw HuskyProfileStoreError.preferencesWriteFailed
    }
  }
}

@Observable
@MainActor
public final class HuskyProfileStore {
  private static let preferencesVersion = 1
  private static let preferencesKey = "com.sirerun.husky.profile-store.v1"
  public static let recoveryBackupKeyPrefix = "com.sirerun.husky.profile-store.recovery-backup."
  public static let recoveryExplanation =
    "Husky can move unreadable profile preferences into a retained recovery backup and clear the active preference record. Backend credentials in Keychain are not changed."
  public private(set) var profiles: [HuskyBackendProfile]
  public private(set) var selectedProfileID: UUID?
  public private(set) var revision: UInt64 = 0

  @ObservationIgnored private let preferences: any HuskyProfilePreferencesBacking
  @ObservationIgnored private let credentials: any HuskyCredentialStore
  @ObservationIgnored private var state: PreferencesState

  /// Invoke only after the user confirms the recovery explanation in the UI.
  /// Raw preference bytes are retained under a unique key; credentials are untouched.
  public static func recoverPreferences(defaults: UserDefaults = .standard) throws {
    guard let original = defaults.data(forKey: Self.preferencesKey) else {
      throw HuskyProfileStoreError.noPreferencesToRecover
    }

    var backupKey: String?
    for _ in 0..<16 {
      let candidate = Self.recoveryBackupKeyPrefix + UUID().uuidString
      guard defaults.object(forKey: candidate) == nil else { continue }
      defaults.set(original, forKey: candidate)
      guard defaults.data(forKey: candidate) == original else {
        throw HuskyProfileStoreError.recoveryBackupVerificationFailed
      }
      backupKey = candidate
      break
    }
    guard backupKey != nil else {
      throw HuskyProfileStoreError.recoveryBackupUnavailable
    }

    guard defaults.data(forKey: Self.preferencesKey) == original else {
      throw HuskyProfileStoreError.recoveryPreferencesChanged
    }
    defaults.removeObject(forKey: Self.preferencesKey)
    guard defaults.object(forKey: Self.preferencesKey) == nil else {
      throw HuskyProfileStoreError.recoveryRemovalFailed
    }
  }

  /// Lists backup key names only; preference and draft contents are never returned.
  public static func recoveryBackupKeys(defaults: UserDefaults = .standard) -> [String] {
    defaults.dictionaryRepresentation().keys
      .filter { $0.hasPrefix(Self.recoveryBackupKeyPrefix) }
      .sorted()
  }

  public convenience init(
    defaults: UserDefaults = .standard,
    credentials: any HuskyCredentialStore = HuskyKeychainCredentialStore()
  ) throws {
    try self.init(
      preferences: UserDefaultsHuskyProfilePreferences(defaults: defaults),
      credentials: credentials
    )
  }

  init(
    preferences: any HuskyProfilePreferencesBacking,
    credentials: any HuskyCredentialStore
  ) throws {
    self.preferences = preferences
    self.credentials = credentials

    if let data = preferences.load() {
      let header: PreferencesVersion
      do {
        header = try JSONDecoder().decode(PreferencesVersion.self, from: data)
      } catch {
        throw HuskyProfileStoreError.invalidPreferences
      }
      guard header.version == Self.preferencesVersion else {
        throw HuskyProfileStoreError.unsupportedPreferencesVersion(header.version)
      }
      let decoded: PreferencesState
      do {
        decoded = try JSONDecoder().decode(PreferencesState.self, from: data)
      } catch {
        throw HuskyProfileStoreError.invalidPreferences
      }
      guard decoded.version == Self.preferencesVersion else {
        throw HuskyProfileStoreError.unsupportedPreferencesVersion(decoded.version)
      }
      try Self.validate(decoded)
      self.state = decoded
      self.profiles = decoded.profiles
      self.selectedProfileID = decoded.selectedProfileID
    } else {
      let empty = PreferencesState.empty
      self.state = empty
      self.profiles = []
      self.selectedProfileID = nil
    }
  }

  public func save(_ profile: HuskyBackendProfile, token: String? = nil) throws {
    _ = try profile.validatedEndpoint()
    let existingIndex = self.state.profiles.firstIndex { $0.id == profile.id }
    var next = self.state
    if let existingIndex {
      next.profiles[existingIndex] = profile
    } else {
      next.profiles.append(profile)
    }

    if let token {
      try self.commit(next, credentialChange: .set(token, profile.id))
    } else {
      try self.commit(next)
    }
  }

  public func delete(id: UUID) throws {
    guard self.state.profiles.contains(where: { $0.id == id }) else {
      throw HuskyProfileStoreError.profileNotFound
    }
    var next = self.state
    next.profiles.removeAll { $0.id == id }
    if next.selectedProfileID == id { next.selectedProfileID = nil }
    next.drafts.removeAll { $0.profileID == id }
    next.lastConversations.removeAll { $0.profileID == id }
    try self.commit(next, credentialChange: .delete(id))
  }

  public func select(id: UUID?) throws {
    if let id, !self.state.profiles.contains(where: { $0.id == id }) {
      throw HuskyProfileStoreError.invalidSelection
    }
    var next = self.state
    next.selectedProfileID = id
    try self.commit(next)
  }

  public func token(for id: UUID) throws -> String? {
    guard self.state.profiles.contains(where: { $0.id == id }) else {
      throw HuskyProfileStoreError.profileNotFound
    }
    return try self.credentials.read(profileID: id)
  }

  public func draft(profileID: UUID, conversationID: String) -> HuskyDraftRecord {
    _ = self.revision
    return self.state.drafts.first {
      $0.profileID == profileID && $0.conversationID == conversationID
    }?.record ?? HuskyDraftRecord(text: "")
  }

  public func setDraft(
    _ draft: HuskyDraftRecord,
    profileID: UUID,
    conversationID: String
  ) throws {
    guard self.state.profiles.contains(where: { $0.id == profileID }) else {
      throw HuskyProfileStoreError.profileNotFound
    }
    try Self.validateConversationID(conversationID)
    try Self.validate(draft)

    var next = self.state
    next.drafts.removeAll {
      $0.profileID == profileID && $0.conversationID == conversationID
    }
    if draft != HuskyDraftRecord(text: "") {
      next.drafts.append(
        StoredDraft(profileID: profileID, conversationID: conversationID, record: draft))
    }
    try self.commit(next)
  }

  public func lastConversation(profileID: UUID) -> String? {
    _ = self.revision
    return self.state.lastConversations.first { $0.profileID == profileID }?.conversationID
  }

  public func setLastConversation(_ conversationID: String?, profileID: UUID) throws {
    guard self.state.profiles.contains(where: { $0.id == profileID }) else {
      throw HuskyProfileStoreError.profileNotFound
    }
    if let conversationID { try Self.validateConversationID(conversationID) }

    var next = self.state
    next.lastConversations.removeAll { $0.profileID == profileID }
    if let conversationID {
      next.lastConversations.append(
        StoredLastConversation(profileID: profileID, conversationID: conversationID))
    }
    try self.commit(next)
  }

  private enum CredentialChange {
    case set(String, UUID)
    case delete(UUID)

    var profileID: UUID {
      switch self {
      case .set(_, let id), .delete(let id): id
      }
    }
  }

  private func commit(_ next: PreferencesState, credentialChange: CredentialChange? = nil) throws {
    try Self.validate(next)

    guard let credentialChange else {
      try self.persist(next)
      return
    }

    let profileID = credentialChange.profileID
    let previousToken = try self.credentials.read(profileID: profileID)
    do {
      switch credentialChange {
      case .set(let token, let id):
        if token.isEmpty {
          try self.credentials.delete(profileID: id)
        } else {
          try self.credentials.write(token, profileID: id)
        }
      case .delete(let id):
        try self.credentials.delete(profileID: id)
      }
    } catch {
      do {
        try self.restoreCredential(previousToken, profileID: profileID)
      } catch {
        throw HuskyProfileStoreError.transactionRollbackFailed
      }
      throw error
    }

    do {
      try self.persist(next)
    } catch {
      do {
        try self.restoreCredential(previousToken, profileID: profileID)
      } catch {
        throw HuskyProfileStoreError.transactionRollbackFailed
      }
      throw error
    }
  }

  private func restoreCredential(_ token: String?, profileID: UUID) throws {
    if let token {
      try self.credentials.write(token, profileID: profileID)
    } else {
      try self.credentials.delete(profileID: profileID)
    }
  }

  private func persist(_ next: PreferencesState) throws {
    let data: Data
    do {
      data = try JSONEncoder().encode(next)
    } catch {
      throw HuskyProfileStoreError.preferencesWriteFailed
    }
    let previousData = self.preferences.load()
    do {
      try self.preferences.save(data)
    } catch {
      do {
        try self.preferences.save(previousData)
      } catch {
        throw HuskyProfileStoreError.transactionRollbackFailed
      }
      throw HuskyProfileStoreError.preferencesWriteFailed
    }
    self.state = next
    self.profiles = next.profiles
    self.selectedProfileID = next.selectedProfileID
    self.revision &+= 1
  }

  private static func validate(_ state: PreferencesState) throws {
    guard state.version == Self.preferencesVersion else {
      throw HuskyProfileStoreError.unsupportedPreferencesVersion(state.version)
    }
    var profileIDs = Set<UUID>()
    for profile in state.profiles {
      guard profileIDs.insert(profile.id).inserted else {
        throw HuskyProfileStoreError.duplicateProfileID
      }
      _ = try profile.validatedEndpoint()
    }
    if let selectedProfileID = state.selectedProfileID,
      !profileIDs.contains(selectedProfileID)
    {
      throw HuskyProfileStoreError.invalidSelection
    }
    var draftKeys = Set<String>()
    for draft in state.drafts {
      guard profileIDs.contains(draft.profileID) else {
        throw HuskyProfileStoreError.profileNotFound
      }
      try Self.validateConversationID(draft.conversationID)
      try Self.validate(draft.record)
      let key = "\(draft.profileID.uuidString):\(draft.conversationID)"
      guard draftKeys.insert(key).inserted else {
        throw HuskyProfileStoreError.invalidPreferences
      }
    }
    var conversationProfileIDs = Set<UUID>()
    for lastConversation in state.lastConversations {
      guard profileIDs.contains(lastConversation.profileID) else {
        throw HuskyProfileStoreError.profileNotFound
      }
      try Self.validateConversationID(lastConversation.conversationID)
      guard conversationProfileIDs.insert(lastConversation.profileID).inserted else {
        throw HuskyProfileStoreError.invalidPreferences
      }
    }
  }

  private static func validate(_ draft: HuskyDraftRecord) throws {
    switch (draft.pendingRequestID, draft.pendingText) {
    case (nil, nil): return
    case (.some(let requestID), .some):
      guard !requestID.isEmpty, requestID.utf8.count <= 256 else {
        throw HuskyProfileStoreError.invalidDraft
      }
    default:
      throw HuskyProfileStoreError.invalidDraft
    }
  }

  private static func validateConversationID(_ conversationID: String) throws {
    guard !conversationID.isEmpty, conversationID.utf8.count <= 256 else {
      throw HuskyProfileStoreError.invalidConversationID
    }
  }

  private struct StoredDraft: Codable {
    let profileID: UUID
    let conversationID: String
    let record: HuskyDraftRecord
  }

  private struct StoredLastConversation: Codable {
    let profileID: UUID
    let conversationID: String
  }

  private struct PreferencesVersion: Decodable {
    let version: Int
  }

  private struct PreferencesState: Codable {
    let version: Int
    var profiles: [HuskyBackendProfile]
    var selectedProfileID: UUID?
    var drafts: [StoredDraft]
    var lastConversations: [StoredLastConversation]

    static let empty = PreferencesState(
      version: 1,
      profiles: [],
      selectedProfileID: nil,
      drafts: [],
      lastConversations: []
    )
  }
}
