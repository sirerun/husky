import Foundation
import Observation
import XCTest

@testable import HuskyCore

@MainActor
final class HuskyProfileStoreTests: XCTestCase {
  func testEndpointValidationRequiresTLSExceptExplicitLiteralLoopback() throws {
    let secure = HuskyBackendProfile(name: "Remote", endpoint: "https://chat.example:8443")
    XCTAssertEqual(
      try secure.validatedEndpoint(),
      HuskyEndpoint(host: "chat.example", port: 8443, usesTLS: true)
    )

    let loopback = HuskyBackendProfile(
      name: "Fixture",
      endpoint: "http://127.0.0.2:50051",
      allowsInsecureLoopback: true
    )
    XCTAssertEqual(
      try loopback.validatedEndpoint(),
      HuskyEndpoint(host: "127.0.0.2", port: 50_051, usesTLS: false)
    )

    let ipv6Loopback = HuskyBackendProfile(
      name: "IPv6 fixture",
      endpoint: "http://[::1]:50051",
      allowsInsecureLoopback: true
    )
    XCTAssertEqual(try ipv6Loopback.validatedEndpoint().port, 50_051)
    XCTAssertFalse(try ipv6Loopback.validatedEndpoint().usesTLS)

    let ipv4Loopback = HuskyBackendProfile(
      name: "IPv4 fixture",
      endpoint: "http://127.0.0.1:50051",
      allowsInsecureLoopback: true
    )
    XCTAssertEqual(try ipv4Loopback.validatedEndpoint().host, "127.0.0.1")
  }

  func testEndpointValidationRejectsCredentialsPathsQueriesFragmentsAndNonLoopbackHTTP() {
    let invalidEndpoints = [
      "http://localhost:50051",
      "http://192.168.1.10:50051",
      "http://127.00.0.1:50051",
      "https://user:password@chat.example",
      "https://chat.example/path",
      "https://chat.example?token=secret",
      "https://chat.example#fragment",
      "ftp://chat.example",
      "https://chat.example:70000",
      "https://chat.example:0",
      "https://chat.example:8443\n",
      "https://chat .example:8443",
    ]

    for endpoint in invalidEndpoints {
      let profile = HuskyBackendProfile(
        name: "Test", endpoint: endpoint, allowsInsecureLoopback: true)
      XCTAssertThrowsError(try profile.validatedEndpoint(), "Accepted \(endpoint)")
    }

    XCTAssertThrowsError(
      try HuskyBackendProfile(name: "   ", endpoint: "https://chat.example").validatedEndpoint())
  }

  func testProfilesSelectionCredentialsDraftsAndConversationPreferencesRoundTrip() throws {
    let suite = "HuskyProfileStoreTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let credentials = FakeCredentialStore()
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    let store = try HuskyProfileStore(defaults: defaults, credentials: credentials)

    try store.save(profile, token: "private-token-value")
    try store.select(id: profile.id)
    try store.setDraft(
      HuskyDraftRecord(
        text: "current draft",
        pendingRequestID: "request-7",
        pendingText: "already submitted text"
      ),
      profileID: profile.id,
      conversationID: "conversation-3"
    )
    try store.setLastConversation("conversation-3", profileID: profile.id)

    let encodedPreferences = try XCTUnwrap(defaults.data(forKey: Self.preferencesKey))
    XCTAssertFalse(String(decoding: encodedPreferences, as: UTF8.self).contains("private-token"))

    let reopened = try HuskyProfileStore(defaults: defaults, credentials: credentials)
    XCTAssertEqual(reopened.profiles, [profile])
    XCTAssertEqual(reopened.selectedProfileID, profile.id)
    XCTAssertEqual(try reopened.token(for: profile.id), "private-token-value")
    XCTAssertEqual(
      reopened.draft(profileID: profile.id, conversationID: "conversation-3"),
      HuskyDraftRecord(
        text: "current draft",
        pendingRequestID: "request-7",
        pendingText: "already submitted text"
      )
    )
    XCTAssertEqual(reopened.lastConversation(profileID: profile.id), "conversation-3")
    XCTAssertEqual(reopened.draft(profileID: profile.id, conversationID: "other"), .init(text: ""))
  }

  func testNilTokenPreservesAndEmptyTokenRemovesCredential() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")

    try store.save(profile, token: "first-token")
    try store.save(profile)
    XCTAssertEqual(try store.token(for: profile.id), "first-token")

    try store.save(profile, token: "")
    XCTAssertNil(try store.token(for: profile.id))
    XCTAssertEqual(store.profiles, [profile])
  }

  func testCredentialWriteFailureLeavesProfilePreferencesUntouched() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    credentials.failNextWrite = true

    XCTAssertThrowsError(try store.save(profile, token: "private-token"))
    XCTAssertTrue(store.profiles.isEmpty)
    XCTAssertNil(store.selectedProfileID)
    XCTAssertNil(preferences.data)
  }

  func testCredentialWriteFailureAfterMutationRestoresPreviousCredential() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let original = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(original, token: "original-token")
    credentials.failNextWrite = true
    credentials.mutateBeforeFailNextWrite = true
    let updated = HuskyBackendProfile(
      id: original.id, name: "Renamed", endpoint: "https://chat.example")

    XCTAssertThrowsError(try store.save(updated, token: "replacement-token"))
    XCTAssertEqual(store.profiles, [original])
    XCTAssertEqual(try store.token(for: original.id), "original-token")
  }

  func testPreferenceFailureRollsBackCredentialAndLeavesObservableStateUntouched() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let original = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(original, token: "original-token")
    let originalRevision = store.revision
    let originalPreferences = preferences.data
    let updated = HuskyBackendProfile(
      id: original.id, name: "Renamed", endpoint: "https://chat.example")
    preferences.failNextSave = true
    preferences.mutateBeforeFailNextSave = true

    XCTAssertThrowsError(try store.save(updated, token: "replacement-token"))
    XCTAssertEqual(store.profiles, [original])
    XCTAssertEqual(store.revision, originalRevision)
    XCTAssertEqual(try store.token(for: original.id), "original-token")
    XCTAssertEqual(preferences.data, originalPreferences)
    XCTAssertEqual(preferences.saveCount, 3)
  }

  func testFailedCredentialDeleteLeavesProfileDraftAndSelectionUntouched() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(profile, token: "original-token")
    try store.select(id: profile.id)
    let draft = HuskyDraftRecord(text: "keep me")
    try store.setDraft(draft, profileID: profile.id, conversationID: "conversation-1")
    credentials.failNextDelete = true
    credentials.mutateBeforeFailNextDelete = true

    XCTAssertThrowsError(try store.delete(id: profile.id))
    XCTAssertEqual(store.profiles, [profile])
    XCTAssertEqual(store.selectedProfileID, profile.id)
    XCTAssertEqual(store.draft(profileID: profile.id, conversationID: "conversation-1"), draft)
    XCTAssertEqual(try store.token(for: profile.id), "original-token")
  }

  func testDeleteRemovesProfileScopedDataAndCredential() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(profile, token: "original-token")
    try store.select(id: profile.id)
    try store.setDraft(
      HuskyDraftRecord(text: "draft"), profileID: profile.id, conversationID: "conversation-1")
    try store.setLastConversation("conversation-1", profileID: profile.id)

    try store.delete(id: profile.id)

    XCTAssertTrue(store.profiles.isEmpty)
    XCTAssertNil(store.selectedProfileID)
    XCTAssertEqual(
      store.draft(profileID: profile.id, conversationID: "conversation-1"), .init(text: ""))
    XCTAssertNil(store.lastConversation(profileID: profile.id))
    XCTAssertNil(try credentials.read(profileID: profile.id))
  }

  func testDeletePreferenceFailureRestoresCredentialAndKeepsProfile() throws {
    let preferences = FakePreferencesBacking()
    let credentials = FakeCredentialStore()
    let store = try HuskyProfileStore(preferences: preferences, credentials: credentials)
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(profile, token: "original-token")
    preferences.failNextSave = true

    XCTAssertThrowsError(try store.delete(id: profile.id))
    XCTAssertEqual(store.profiles, [profile])
    XCTAssertEqual(try store.token(for: profile.id), "original-token")
  }

  func testDraftRequiresPendingRequestAndPayloadTogether() throws {
    let preferences = FakePreferencesBacking()
    let store = try HuskyProfileStore(preferences: preferences, credentials: FakeCredentialStore())
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(profile)

    XCTAssertThrowsError(
      try store.setDraft(
        HuskyDraftRecord(text: "draft", pendingRequestID: "request-1"),
        profileID: profile.id,
        conversationID: "conversation-1"
      ))
    XCTAssertThrowsError(
      try store.setDraft(
        HuskyDraftRecord(text: "draft", pendingRequestID: "", pendingText: "payload"),
        profileID: profile.id,
        conversationID: "conversation-1"
      ))
    XCTAssertEqual(preferences.saveCount, 1)
  }

  func testDraftAndLastConversationReadsObserveSuccessfulWrites() throws {
    let preferences = FakePreferencesBacking()
    let store = try HuskyProfileStore(preferences: preferences, credentials: FakeCredentialStore())
    let profile = HuskyBackendProfile(name: "Work", endpoint: "https://chat.example")
    try store.save(profile)
    let draftChangeObserved = ObservationFlag()
    withObservationTracking {
      _ = store.draft(profileID: profile.id, conversationID: "conversation-1")
    } onChange: {
      draftChangeObserved.set()
    }

    try store.setDraft(
      HuskyDraftRecord(text: "new draft"),
      profileID: profile.id,
      conversationID: "conversation-1"
    )
    XCTAssertTrue(draftChangeObserved.value)

    let conversationChangeObserved = ObservationFlag()
    withObservationTracking {
      _ = store.lastConversation(profileID: profile.id)
    } onChange: {
      conversationChangeObserved.set()
    }
    try store.setLastConversation("conversation-1", profileID: profile.id)
    XCTAssertTrue(conversationChangeObserved.value)
  }

  func testUnsupportedAndCorruptPreferencesFailClosed() throws {
    let futurePreferences = FakePreferencesBacking(
      data: Data("{\"version\":99}".utf8))
    XCTAssertThrowsError(
      try HuskyProfileStore(
        preferences: futurePreferences, credentials: FakeCredentialStore())
    ) {
      XCTAssertEqual(
        $0 as? HuskyProfileStoreError, .unsupportedPreferencesVersion(99))
    }

    let corruptPreferences = FakePreferencesBacking(data: Data("not-json".utf8))
    XCTAssertThrowsError(
      try HuskyProfileStore(
        preferences: corruptPreferences, credentials: FakeCredentialStore())
    ) {
      XCTAssertEqual($0 as? HuskyProfileStoreError, .invalidPreferences)
    }
  }

  func testNonDataUserDefaultsPreferencesFailClosed() throws {
    let suite = "HuskyProfileStoreNonDataTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let original: [String: String] = ["preserve": "this value"]
    defaults.set(original, forKey: Self.preferencesKey)

    XCTAssertThrowsError(
      try HuskyProfileStore(defaults: defaults, credentials: FakeCredentialStore())
    ) {
      XCTAssertEqual($0 as? HuskyProfileStoreError, .invalidPreferences)
    }
    XCTAssertEqual(defaults.dictionary(forKey: Self.preferencesKey) as? [String: String], original)
  }

  func testExplicitRecoveryKeepsRawBytesUnderNewBackupAndPreservesOldBackups() throws {
    let suite = "HuskyProfileRecoveryTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let original = Data([0x7b, 0xff, 0x00, 0x7d])
    let existingBackupKey = HuskyProfileStore.recoveryBackupKeyPrefix + "existing"
    let existingBackup = Data("keep this backup".utf8)
    defaults.set(original, forKey: Self.preferencesKey)
    defaults.set(existingBackup, forKey: existingBackupKey)

    try HuskyProfileStore.recoverPreferences(defaults: defaults)

    XCTAssertNil(defaults.object(forKey: Self.preferencesKey))
    XCTAssertEqual(defaults.data(forKey: existingBackupKey), existingBackup)
    let backupKeys = HuskyProfileStore.recoveryBackupKeys(defaults: defaults)
    XCTAssertEqual(backupKeys.count, 2)
    let newBackupKey = try XCTUnwrap(backupKeys.first { $0 != existingBackupKey })
    XCTAssertEqual(defaults.data(forKey: newBackupKey), original)
    XCTAssertTrue(HuskyProfileStore.recoveryExplanation.contains("Keychain"))
  }

  func testRecoveryWithoutRawPreferencesFailsWithoutChangingExistingValue() throws {
    let suite = "HuskyProfileRecoveryTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("preserve this value", forKey: Self.preferencesKey)

    XCTAssertThrowsError(try HuskyProfileStore.recoverPreferences(defaults: defaults)) {
      XCTAssertEqual($0 as? HuskyProfileStoreError, .invalidPreferences)
    }
    XCTAssertEqual(defaults.string(forKey: Self.preferencesKey), "preserve this value")
    XCTAssertTrue(HuskyProfileStore.recoveryBackupKeys(defaults: defaults).isEmpty)
  }

  private static let preferencesKey = "com.sirerun.husky.profile-store.v1"

}

private final class FakeCredentialStore: HuskyCredentialStore, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UUID: String] = [:]
  var failNextWrite = false
  var failNextDelete = false
  var mutateBeforeFailNextWrite = false
  var mutateBeforeFailNextDelete = false

  func read(profileID: UUID) throws -> String? {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.values[profileID]
  }

  func write(_ token: String, profileID: UUID) throws {
    self.lock.lock()
    defer { self.lock.unlock() }
    if self.failNextWrite {
      self.failNextWrite = false
      if self.mutateBeforeFailNextWrite {
        self.values[profileID] = token
        self.mutateBeforeFailNextWrite = false
      }
      throw HuskyProfileStoreError.credentialOperationFailed(operation: "write", status: -1)
    }
    self.values[profileID] = token
  }

  func delete(profileID: UUID) throws {
    self.lock.lock()
    defer { self.lock.unlock() }
    if self.failNextDelete {
      self.failNextDelete = false
      if self.mutateBeforeFailNextDelete {
        self.values.removeValue(forKey: profileID)
        self.mutateBeforeFailNextDelete = false
      }
      throw HuskyProfileStoreError.credentialOperationFailed(operation: "delete", status: -1)
    }
    self.values.removeValue(forKey: profileID)
  }
}

private final class ObservationFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var isSet = false

  var value: Bool {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.isSet
  }

  func set() {
    self.lock.lock()
    defer { self.lock.unlock() }
    self.isSet = true
  }
}

@MainActor
private final class FakePreferencesBacking: HuskyProfilePreferencesBacking {
  var data: Data?
  var failNextSave = false
  var mutateBeforeFailNextSave = false
  private(set) var saveCount = 0

  init(data: Data? = nil) {
    self.data = data
  }

  func load() throws -> Data? {
    self.data
  }

  func save(_ data: Data?) throws {
    self.saveCount += 1
    if self.failNextSave {
      self.failNextSave = false
      if self.mutateBeforeFailNextSave {
        self.data = data
        self.mutateBeforeFailNextSave = false
      }
      throw HuskyProfileStoreError.preferencesWriteFailed
    }
    self.data = data
  }
}
