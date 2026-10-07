# Connecting a backend

Husky is a typed-text client for the versioned `husky.v1.HuskyBackend` service in
`Packages/HuskyProtocol/Sources/HuskyProtocol/v1/husky.proto`. A backend owns
conversation history and assistant execution. Husky does not execute tools,
capture audio, or provide a hosted assistant.

## Connection settings

Open **Connect → Connection settings**, enter a name and `https://host:port`,
then save and connect. Remote connections use system certificate trust and
hostname verification. URLs must not contain credentials, paths, queries or
fragments. HTTP requires the explicit local development option and a literal
loopback address, such as `http://127.0.0.1:50051`.

Selecting **Replace saved token** stores a new bearer token in the macOS Keychain;
an empty replacement removes it. Leaving replacement unchecked preserves the
existing token. The client sends `authorization: Bearer <token>` metadata on
every unary and conversation-stream RPC. Servers must authenticate every RPC
and enforce conversation authorization themselves. Do not put tokens in URLs.
Husky never disables TLS verification.

Profiles, the selected conversation and user-authored drafts use local preferences.
Tokens use a separate per-profile Keychain item. Deleting a profile removes its
local drafts and token; it does not delete backend conversations or messages.
The client does not maintain a local database of backend history.

## Implementing the service

Implement GetCapabilities, ListConversations, CreateConversation, GetHistory and
ConversationSession from the schema. See
[the frozen wire contract](contracts/husky-v1-foundation-freeze.md) for exact
limits, cursor semantics and event ordering. Validate capabilities before serving
messages. Use opaque stable conversation/message/request identifiers and stable
history snapshots. History pages are oldest-to-newest within one snapshot;
continuation cursors retain that snapshot. A live stream resumes after the last
applied sequence and may include a resume token. Expired or incompatible cursors
must produce explicit resynchronization, not silently omit events.

Submission acknowledgement is separate from transport enqueue. Preserve a
request ID's original payload and return a replay acknowledgement on an identical
retry; reject reuse with changed content. The client saves pending ID and payload
before sending and retains them after ambiguous failure. Only acceptance clears
the corresponding draft. Never interpret reconnect as permission to resubmit
with a new ID. Cancellation acknowledgement after completion is cursor-neutral.

## Local fixture

Build with the repository's supported Swift toolchain, then run
`swift run HuskyFixtureServer --fixture-mode`. The fixture binds loopback on port
50051 by default. In the normal Husky app create a connection to
`http://127.0.0.1:50051`, explicitly enable local HTTP and create a conversation.
The fixture deliberately generates deterministic text; it is not an AI service.
`--demo` remains a static appearance sample and `--fixture-mode` retains the
original foundation demonstration path. Use a saved local profile to exercise
the complete client controls.

## Delivery evidence

Source and focused tests for this client are under active verification. This
document describes the intended implemented interface, not production-backend,
signed-release, installation or automatic-update acceptance. Recorded exact
revision checks and remaining native gates live in [the plan](plan.md) and
[development log](devlog.md).
