# Husky design

Status: confirmed product requirements and proposed engineering design, 2026-10-03. No implemented or released behavior is claimed.

## Product boundary

Husky is a generic native macOS desktop chat client. It sends typed messages to one active backend and receives streamed text responses and status events. The backend owns history and response decisions, including when it responds to input from other producers. Husky has no microphone access, recording controls, transcription dependency, or coupling to external listening services.

Users save multiple backend profiles, select one at a time, and switch between multiple backend-owned conversations. Systems integrate by implementing the common Husky gRPC API directly or through an adapter. Supporting an arbitrary existing API without that adapter is not promised.

## Native interface

An AppKit NSPanel owns desktop placement, floating level, dragging, keyboard focus and lifecycle. SwiftUI supplies the conversation, composer, lightweight profile/conversation controls, and settings, with AppKit text input/material wrappers as needed.

The floating window is frameless/borderless, with no title bar or opaque rectangular background. Its background and unused margins are transparent; glass tint/material is confined to bubbles and composer. Composer and recent bubbles appear together at launch. The entire conversation moves as a unit, initially at the bottom left of the active display’s visible frame, inset from the Dock and screen edges, and older messages remain scrollable in both directions. Incoming events must not steal typing focus from another application. Scroll position is preserved while reading history; new events follow only when the reader is at the bottom. Provide an accessible route to full history without the soft top fade obscuring content.

The visual reference is the supplied glass-chat-2 `dist/` bundle. Reproduce the floating chat, not the surrounding demo webpage/background. Preserve its bubble layout, padding, alternating alignment, subtle outlines/highlights, circular send control, growing composer, and top alpha fade. Reference tokens: 560 px max width, 26 px corners, 18 px message gap, 22 px blur, 13% base tint, 110 px fade, 87% bubble width, 18 px body text, and approximately 510 px scroll-region height constrained by available space. Translating CSS pixels into native points requires visual validation on the target display.

Use behind-window NSVisualEffectView as the initial material candidate, clipped per bubble/composer with custom visual layers. Native materials pick up content behind the app; a CSS blur radius is not a directly controllable equivalent. NSGlassEffectView on macOS 26+ is an alternative to evaluate, not an automatic replacement for the requested appearance. Compare actual native output on light, dark, and busy backgrounds. The user's appearance requirement takes precedence over generic skill spacing/material preferences.

The reference explicitly switches text tone for light scenes; it does not automatically measure the screen. Use native contrast/vibrancy and accessible appearance controls/fallback surfaces. Do not add screen-capture permissions or imply guaranteed contrast over every backdrop. Reduced transparency/motion and keyboard/VoiceOver use require native evidence. Transparent margins and interactive conversation areas need deliberate hit testing so scrolling remains possible without unexpectedly blocking underlying apps.

Default compatibility proposal: macOS 15+ on Apple Silicon, qualified against pinned dependency versions. Bottom-left placement applies on first launch or explicit position reset; a valid user-dragged saved position takes precedence on later launches. Position restores per display and stays reachable after monitor changes. Define menu-bar hide/summon and keyboard behavior during implementation; no login-at-startup is assumed.

## Backend contract

Use versioned `husky.v1` Protocol Buffers and native gRPC Swift 2 transport. The protocol includes capability/version negotiation, conversation list/create, cursor-paginated history, and a bidirectional live stream. The live stream receives typed submissions/cancellation and emits canonical messages, text deltas/completion, status, and independently initiated backend updates. A request/response-only design cannot satisfy unsolicited backend updates.

The foundation must define stable profile-scoped conversation IDs, canonical message IDs, client request IDs for idempotency, per-conversation event sequence/cursors, delta replacement semantics, and a history snapshot/live-stream boundary. Reconnect resumes when supported and otherwise reconciles canonical history. Never blindly retry a submission that could already be accepted. Limits, deadlines, explicit authentication/compatibility failures, and resync conditions form part of the public contract.

Switching backend or conversation cancels/detaches the previous stream and fences delayed events with a connection generation. Data and drafts stay scoped to profile/conversation. Persist endpoint/profile preferences and drafts locally; store credentials in Keychain. Message history remains authoritative on the backend and is not copied into an offline history database in v1.

Require TLS for remote profiles. Any local plaintext fixture configuration is explicit development mode. Start with token metadata authentication and qualify backend requirements during preflight; do not invent automatic OAuth delegation. Publish protobuf files, generation instructions, and a deterministic real-gRPC conformance fixture so independent systems can build adapters without depending on the app source.

## Build and distribution

Use an Xcode macOS app target with SwiftPM dependencies and testable core/protocol packages. Pin actual dependencies and generated-code tools after compatibility checks. Use native tests and actual gRPC requests, not browser tests or mocks alone, for acceptance.

Release Husky source under Apache-2.0. Preserve required dependency notices in source and the packaged app. A NOTICE file is included when required by incorporated notices or useful project attribution; do not mislabel all dependencies as Apache-2.0.

Proposed direct distribution: immutable version tags/assets in public GitHub Releases, with a stable HTTPS appcast on GitHub Pages. Adopt Sparkle 2 for update discovery, archive validation, installation, and relaunch. Verify the feed endpoint is publicly reachable before embedding it in a release. Code-sign/notarize the application and included helpers; EdDSA-sign update archives and keep signing keys out of the app/repository. Qualify signed-feed support against the pinned Sparkle version.

Automatic updates run in the background and install when safe, preserving local settings/drafts and avoiding interruption of active conversations. Include a manual update check and user opt-out. Safe failures retain the currently installed app. Real completion requires two published, reviewed release revisions and an observed automatic upgrade on the local Mac.

## Evidence boundaries

The conformance fixture proves Husky's generic API behavior, not compatibility with any untested backend or hosted AI product. Local developer builds do not prove signed distribution. Signed artifacts do not prove local installation. A reachable feed does not prove automatic installation. Native/reference fidelity, published artifact launch, and actual successor update each require their own evidence.
