# E2 client interface and ownership

Status: frozen 2026-10-06 after PR #5 independent review and landing at `ec984fb`. Transport pins remain unchanged; the additive `husky.v1` partial-snapshot extension is specified below. Coordinator may correct a seam with affected workers before implementation; do not invent worker-local variants.

## Ownership

- Profiles worker: `Packages/HuskyCore/Sources/HuskyCore/HuskyProfileStore.swift` and focused profile tests only.
- Conversation worker: `Packages/HuskyCore/Sources/HuskyCore/HuskyConversationController.swift` and focused controller tests only.
- Native worker: window lifecycle controller, standalone windowing geometry module and its tests. No chat view/model or root package edits.
- Coordinator: root package/CI, app/client/view integration, transport metadata/factory, docs/plan, signing/update/release wiring in later tasks.

## Profile seam

`HuskyBackendProfile`: public Codable/Sendable/Equatable/Identifiable value with UUID `id`, `name: String`, `endpoint: String`, `allowsInsecureLoopback: Bool`. Validation returns `HuskyEndpoint(host: String, port: Int, usesTLS: Bool)`. Reject credentials, query/fragment/path in endpoint URLs; HTTPS is normal, HTTP requires explicit loopback development and a literal loopback host. Never relax certificate/hostname verification.

`HuskyDraftRecord`: public Codable/Sendable/Equatable value with `text: String`, `pendingRequestID: String?`, `pendingText: String?`. Pending text and ID stay paired through ambiguous send/restart; no automatic retry with a new ID. Drafts contain user-authored local text, not a copy of backend history.

`@MainActor @Observable public final class HuskyProfileStore` provides read-only `profiles`, `selectedProfileID`; throwing `init(defaults: UserDefaults = .standard, credentials: any HuskyCredentialStore = HuskyKeychainCredentialStore())`; `save(_ profile: HuskyBackendProfile, token: String? = nil)` (nil preserves existing token, empty removes); `delete(id: UUID)`, `select(id: UUID?)`; `token(for id: UUID) throws -> String?`; `draft(profileID: UUID, conversationID: String) -> HuskyDraftRecord`; `setDraft(_:profileID:conversationID:)`; `lastConversation(profileID:) -> String?`, `setLastConversation(_:profileID:)`. Mutating persistence methods throw. Token never becomes observable state or preference data. Credential adapter injectable; tests use fake store. Service `com.sirerun.husky.backend-token`, account profile UUID; ordinary Keychain item CRUD only, no keychain/search-list/signing changes.

## Conversation seam

`@MainActor @Observable public final class HuskyConversationController` is UI-independent and owns transient backend history and generation-fenced operations using existing `any HuskyChatClient`. Public read-only properties: `messages: [HuskyMessage]`, `conversations: [HuskyConversation]`, `selectedConversationID: String?`, `hasMoreHistory`, `hasMoreConversations`, `isLoading`, `isLoadingHistory`, `isConnected`, `statusText: String?`, `activeRequestID: String?`.

Methods: `attach(profileID: UUID, client: any HuskyChatClient, preferredConversationID: String? = nil) async`; `detach() async`; `selectConversation(id: String) async`; `createConversation(title: String) async`; `loadOlderMessages() async`; `loadMoreConversations() async`; `submit(text: String, requestID: String) async -> Bool` (true only upon matching backend acceptance); `cancelActiveRequest() async`; `reconnect() async`. All operations publish safe errors through statusText. Stable request ID/payload is caller-owned and persisted in the draft record before first submission. Reject changed payload for an outstanding ID; timeout/disconnect returns false without claiming rejection or clearing the draft. Generation-fence all awaited unary/event/cleanup paths; old callbacks must never mutate a newly selected scope. Bound waits and cleanup; do not await a hostile peer indefinitely on switch/shutdown.

Initial history establishes stream snapshot; recovery uses last applied sequence/resume token where possible, refreshes canonical snapshot on resync/gap, and never blindly resends a submission. Older pages merge by ID without overwriting newer streamed values. No automatic empty-conversation creation on a read operation: explicit user Create owns mutations. Tests inject controllable clients/sessions with real event models; coordinator runs integrated fixture requests.

## Native and integration seam

The new `HuskyWindowing` target exposes existing `HuskyPanelLayout`, `HuskyPanelScreenArea` and `HuskyPanelGeometry` as public value helpers; coordinator adds dependency/imports. Native controller gains live screen-parameter reclamping, explicit `resetPosition()` and optional frame-event diagnostics behind `--window-diagnostics`. Preserve existing AppKit autosave and the default/current user position; do not replace proven source with an invented drag path absent evidence.

Coordinator owns a profile-scoped transport task. It loads a token only into a private metadata boundary, attaches the core controller inside `withGRPCClient`, and cancels/detaches on profile switch. All RPCs receive the same metadata. Normal startup uses saved profiles/settings; demo/fixture flags remain explicit. UI stores drafts before submit, retains ambiguous pending ID/payload, and clears only the accepted record in the originating scope. Color never replaces the existing sender accessibility labels/alignment.

## Integration amendments — 2026-10-06

- Add `HuskySubmissionResult` (`accepted`, `rejected`, `unconfirmed`) and `submitResult(text:requestID:)` while preserving accepted-only Bool `submit`. Definite local validation or backend rejection before acceptance returns rejected, allowing pending fields to clear while retaining editable text. Ambiguous outcomes and scope switches preserve ID/payload. No parsing of human status text to decide persistence.
- ProfileStore provides an explicit user-confirmed `recoverPreferences(defaults:)` for corrupt/unsupported preferences. Preserve raw bytes in a unique verified backup before removing active preferences; never touch Keychain. The error-state UI explains recovery and requires confirmation, with restart after completion.

### Partial-message recovery amendment

`HuskyPartialMessageSnapshot(message: HuskyMessage, revision: UInt64)` carries exact full text and last revision at the cursor. `HuskyHistoryPage.partialMessages` defaults to [] and represents ALL in-progress messages at snapshotSequence, including outside the returned history page. Proto GetHistoryResponse adds field5 `partial_messages` (nested ChatMessage+revision); servers advertise `partial_message_snapshots`. This is additive wire compatibility. Older peers cannot qualify fresh-attach mid-message recovery: fail closed if an unseeded delta arrives; never guess text/revision.

Add a protocol overload `openConversation(conversationID:afterSequence:resumeToken:partialMessages:)`. Existing adapters get a default that forwards empty seeds and rejects nonempty seeds, never silently drops them. The GRPC adapter validates and seeds its stream validator. Controller seeds its validator and displayed rows from initial/canonical history and passes exact in-memory seeds on ordinary reconnect. Seeds must match the cursor's conversation and positive sequence <= cursor, unique IDs, non-user role, validated request IDs, per-message limits, <=64 entries and <=2 MiB aggregate text. Delta revisions remain strictly increasing; completion/failure/cancel remove seeds. Controller must stop automatic recovery on unsupported/unseeded partial semantics rather than reconnect forever. Coordinator owns schema/models/protocol/validator/GRPC; controller worker owns controller/tests; fixture worker owns fixture/service/integration tests.
