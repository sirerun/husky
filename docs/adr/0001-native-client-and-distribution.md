# ADR 0001 — independent native client, common gRPC API, and direct distribution

Date: 2026-10-03

Status: product decisions accepted by the user; stack/distribution details selected for planning and subject to implementation preflight.

## Context

The user wants a generic native desktop chat with movable floating glass bubbles matching an existing reference. The first platform is macOS. Backend systems may receive independent continuous inputs, but Husky is solely the bidirectional typed-chat client. The requested delivery also includes an Apache-licensed public release, local installation, and automatic self-updates.

## Accepted product decisions

1. Float over desktop apps, initially at the bottom right; move composer and bubbles together.
2. Open with composer and recent bubbles visible; support scrolling in both directions.
3. Preserve the provided reference appearance, with environment-influenced translucent bubble surfaces.
4. Keep audio/transcription services independent; Husky has no recording controls or dependency on them.
5. Use gRPC and define a common Husky API that each backend implements directly or via an adapter.
6. Save multiple backend profiles, with one active backend at a time.
7. Support multiple conversations through a lightweight switcher.
8. Backend owns history; Husky fetches and displays it.
9. Typed messages flow out; text responses and status events stream in.
10. Release under Apache License 2.0, install locally, and support automatic self-updates.

## Engineering selections

Use Swift/AppKit for the floating window and OS integration, SwiftUI for UI/state, gRPC Swift 2 and Swift Protobuf for the common API, and Sparkle 2 for direct-distribution updates. Prefer public GitHub Releases and a static GitHub Pages appcast to avoid adding a server or paid hosting. Proposed initial compatibility is macOS 15+/Apple Silicon; pinned-dependency checks determine the final target.

Prefer custom native appearance over substituting stock Liquid Glass without comparison. Behind-window materials need a real prototype: their rendering cannot be assumed to match CSS pixel for pixel.

## Consequences

Native window/focus/material integration is direct, while future non-macOS clients require their own shell. Backend systems must conform or provide an adapter; Husky does not translate arbitrary existing protocols. Credentials/settings/drafts are local, but message history is authoritative on the backend. Automatic-update readiness requires signing, hosting, and a real two-release installation test.

Developer ID/notarization and updater-key availability are open prerequisites. No credential provisioning, release publication, or installation occurs during planning. The empty repository needs a reviewed docs-only genesis before normal code PR delivery; all code candidates then follow independent review and GitHub rebase merge.
