# Husky v1 foundation freeze

Status: T1.0 implementation contract, frozen 2026-10-04. Changes return to the coordinator before dependent lanes proceed.

## Platform and dependencies

- macOS 15.0 minimum, Apple Silicon (`arm64`) for the first qualified build.
- Xcode 27.0 / Swift 6.4 on the coordinator host; use Swift language mode 6.
- gRPC Swift 2.4.3, gRPC Swift NIO transport 2.10.0, gRPC Swift Protobuf 2.4.1, and SwiftProtobuf 1.38.1. Lock exact resolved revisions in `Package.resolved`; preserve the lock file in the application source.
- Use the SwiftPM `GRPCProtobufGenerator` build plugin from `grpc-swift-protobuf`. It uses the pinned SwiftProtobuf package's vendored `protoc`; do not require a machine-global `protoc-gen-grpc-swift-2` binary. The host also has `protoc` 35.1 and `protoc-gen-swift`, but project builds use the package toolchain for reproducibility.
- All selected upstream packages publish Apache-2.0 terms. Record each resolved dependency's license and required notices before distribution; this is not a blanket license claim for future dependencies.
- Proposed bundle identifier: `com.sirerun.husky`. It is not registered or signed by this preflight; confirm availability with the Apple developer account before distribution signing.

## Wire and behavior contract

The canonical schema is [`Packages/HuskyProtocol/Sources/HuskyProtocol/v1/husky.proto`](../../Packages/HuskyProtocol/Sources/HuskyProtocol/v1/husky.proto), package `husky.v1`, service `HuskyBackend`.

- Unary RPCs negotiate `husky.v1` capabilities, list/create backend-owned conversations, and read cursor-paginated history. A zero page size means the advertised default. History pages are ordered oldest to newest within each page. The first page supplies `snapshot_sequence`; its cursor pages refer to the same snapshot. `CreateConversation` is idempotent by client request ID and payload.
- `ConversationSession` is bidirectional. `StartSession` is the first client command and identifies the conversation, last applied sequence, and optional resume token. The server attaches to the event log, replays retained events after that sequence, sends `SessionReady` with the replay watermark, then continues live delivery without a gap. A history fetch and subsequent stream attach have no gap because events after the history `snapshot_sequence` are replayed. Sequence numbers on state-changing conversation events increase strictly per conversation and begin at one; `SessionReady`, `ResyncRequired`, failed-command replies, duplicate replay acknowledgements, and the no-op `RequestCancelled` acknowledgement for an already-completed request use envelope sequence zero and do not advance the event cursor.
- `SubmitMessage` uses a client-generated stable request ID. Repeating the same ID and payload in the same backend profile returns the original canonical acceptance result; a duplicate acknowledgement preserves the original message ID and message sequence and is marked `replayed_idempotent_result`. Reusing the ID with different content is `INVALID_ARGUMENT`. Do not blindly resubmit after an ambiguous disconnect.
- Text deltas have increasing revisions. `replace_text`, when present, replaces all accumulated text; otherwise `append_text` is appended. `MessageCompleted` carries the canonical final text and replaces all prior partial content. Canonical message IDs and event sequences reconcile history with the live stream.
- Status, request failure/cancellation, and independently initiated backend messages use the same stream. Server-originated messages use the same message lifecycle with no client `request_id`. Cancel uses the original request ID and is idempotent; cancellation after completion does not roll back a canonical message. `EndSession` disconnects without cancelling accepted backend work. Switching conversation or backend closes the old stream and fences late events in the client.
- A reconnect resumes after the last fully applied sequence. If the server has expired that point, it emits `ResyncRequired`; the client fetches canonical history again and starts from the returned snapshot sequence. It never merges stale events across a resync boundary.
- IDs are opaque, non-empty UTF-8 strings; clients scope a conversation identity to the saved backend profile. Authentication is connection metadata (bearer token in v1), never a protobuf field. Remote endpoints require TLS. Plaintext is allowed only for an explicitly selected local fixture profile. Unsupported `husky.v1` negotiation is `UNIMPLEMENTED`; auth uses `UNAUTHENTICATED` / `PERMISSION_DENIED`; malformed/oversized data uses `INVALID_ARGUMENT`; missing current state uses `FAILED_PRECONDITION`; event-retention expiry uses `OUT_OF_RANGE` or `ResyncRequired`; `UNAVAILABLE` and `DEADLINE_EXCEEDED` are recoverable only with the same request ID or stream cursor.
- Defaults: 50 history entries per page (maximum 100); 64 KiB UTF-8 message body. Backends publish lower limits through capabilities. Requests have bounded deadlines; an interrupted stream does not cancel accepted backend work. Transport/auth/compatibility failures use gRPC status codes. `UNAUTHENTICATED` and `PERMISSION_DENIED` are not retryable; `INVALID_ARGUMENT` and `FAILED_PRECONDITION` require user or state correction; `UNAVAILABLE` and `DEADLINE_EXCEEDED` may be retried only with the same request ID or stream cursor. Expired event history requires resync.

## Frozen code boundaries

| Owner | Path | Contract |
|---|---|---|
| UI lane | `App/Husky/` | Native SwiftUI content and AppKit panel only; no backend transport, microphone, or fixture behavior. The panel is borderless and transparent, starts bottom-left within the active display's visible frame, and receives the core interface through dependency injection. |
| Protocol lane | `Packages/HuskyProtocol/`, `Packages/HuskyCore/` | Generated bindings, Swift client, and the `HuskyChatClient` async interface for capabilities, conversations, history, submission, cancellation, and sequenced events. The frozen `.proto` above is coordinator-owned until all lanes finish; request schema changes through the coordinator. |
| Fixture lane | `Tools/HuskyFixture/` | Deterministic Swift gRPC server implementing the frozen schema; local plaintext only after explicit fixture selection. Own fixture implementation and conformance tests. |
| Coordinator | root project/CI configuration and integration | Own root `Package.swift`, Xcode project, package pins, CI, and final app-to-client wiring. Do not ask worker lanes to edit these shared files. |

The app view model depends on `HuskyChatClient` and presentation value types from `Packages/HuskyCore/`. The UI lane may define an injected boundary adapter in `App/Husky/`, but it must not invent a second transport or alter the frozen wire contract. The fixture depends on generated protocol types and implements the generated server interface.

## Native visual contract

The accepted design in `docs/design.md` controls: borderless, no title bar or opaque panel rectangle; glass is clipped to bubbles and composer with see-through unused margins; whole chat stack drags; bottom-left placement on first launch or reset; valid saved positions restore. Use the stated glass-chat-2 measurements as starting values and verify the native result in light, dark, busy-background, accessibility, scroll, focus, and monitor/Dock states. Native blur is not assumed to equal CSS blur. Do not capture the desktop or request screen-recording permission.

## Evidence

The foundation will claim only local source, build, fixture, and native evidence actually recorded at T1.3/T1.6. This freeze does not establish a production backend, Developer ID identity, notarization, signing key, public release, installation, Sparkle update feed, or local automatic-update acceptance.

## Upstream references

- [gRPC Swift 2.4.3](https://github.com/grpc/grpc-swift-2/releases/tag/2.4.3)
- [gRPC Swift NIO transport](https://github.com/grpc/grpc-swift-nio-transport/releases/tag/2.10.0)
- [gRPC Swift Protobuf](https://github.com/grpc/grpc-swift-protobuf/releases/tag/2.4.1)
- [SwiftProtobuf 1.38.1](https://github.com/apple/swift-protobuf/releases/tag/1.38.1)
- [gRPC Swift Protobuf code-generation plugin](https://github.com/grpc/grpc-swift-protobuf/blob/main/Sources/GRPCProtobuf/Documentation.docc/Articles/Code-generation-with-the-build-plugin.md)
