# Husky devlog


## 2026-10-06 — Continued delivery planning

Reconciled PR #4 source landing at `c956db9` with still-open native acceptance. Split the growing plan into preserved epic files, expanded E2 into profile/credential/draft, conversation orchestration, authenticated transport, UI and native lifecycle lanes with explicit verification/review/merge/landed tasks. The shared E2 contract fixes ownership and interfaces before implementation. Independent audits confirmed no demonstrated drag source defect, a live display-change gap, missing E2 app wiring, and no signed packaging or updater source yet. Signing and publication readiness remain separate gates. This planning change does not claim new native checks or completed client/release behavior.


## 2026-10-05 — Session closeout and message direction styling

Outgoing user bubbles now have an 8% accent fill and 22% accent outline; incoming bubbles keep their neutral material and 15% primary outline. Text, accessibility labels, alignment, and the 20% smaller panel/bubble geometry remain intact. Strict Swift formatting and patch validation pass. The owner requested source merge and knowledge banking for session shutdown; native drag/restore and the other unverified product/release acceptance gates remain open. Final verification and landing evidence will be recorded in the closeout handoff.

## 2026-10-05 — Explicit chat window move handle

Added a visible header move icon with its own drag gesture, accessibility label/hint, and help text so users can find and grab the floating chat window. `swift build`, the complete Swift test suite (31 tests), strict formatting lint for the changed view, and `git diff --check` pass locally. An independent Luna review found no source blocker. CUA confirms the move handle is exposed in the accessibility tree, but the coordinate-based drag probes did not produce reliable frame movement evidence; retain the native drag/position-restore acceptance gate as open. Draft PR #4 remains blocked from hosted CI because GitHub has not started a runner under the account billing lock.

## 2026-10-05 — T1 local build/tests and fixture round trip; native and delivery gates open

Integrated candidate `1fd2f084a35629bb32df95035d0408101174def3` passes the full Swift test suite: 8 `HuskyFixtureTests` and 23 `HuskyCoreTests` (31 XCTest cases, zero failures). The fixture history test now walks all cursor pages, checks a stable snapshot and ordering, and verifies ten unique messages. The app build passed at `74b10720d5c5964fb444a8fdedff21be6146be07`; later commits changed fixture test code only. Tracked Swift sources under `App/`, `Packages/`, and `Tools/` pass `xcrun swift-format lint --strict`; `git diff --check` and `swift package dump-package` pass at the current test head.

The native app was launched in explicit fixture mode against `HuskyFixtureServer`. Process/socket inspection confirmed the server bound only `127.0.0.1:50051` and the app connected to it. The native accessibility tree showed “Connected to deterministic local gRPC fixture”; sending a message rendered the user bubble, the deterministic backend response, and “Idle — Local deterministic fixture status.” The panel showed the fixture label and no titlebar/chrome. A smoke check scrolled six turns from oldest to newest, toggled full-history mode and restored its fade, and compared Popover against the original HUD material before restoring HUD. Both coordinator-started app and server processes were stopped afterward and port 50051 was free. This is a local round-trip and partial interaction proof, not CI or production backend acceptance.

Independent code-source review most recently passed at `1e0b04f9eccb568b60af2900a31c54bc4b5201b7`, including accepted/started/completed event identity and sequence checks. Later candidate changes are test-only. A native screenshot confirmed the panel rendered, but the complete T1.1 evidence is still open: reference comparison; drag, focus/IME, light/dark and busy backgrounds, visible desktop through margins, fresh-preferences bottom-left launch, saved-position restore, Dock/monitor changes, and Reduce Transparency/Motion. Draft PR #4 is open against base `91b831bd8dd8b16d3a7434fec38a80370c137dc1`. Hosted CI run `37266449370` failed before any job steps because GitHub reports the account is locked due to a billing issue (runner ID 0). No billing settings were changed. T1.1–T1.9 remain unchecked pending that acceptance, successful CI, fresh full T1.4 exact-head review, merge, and landed verification. No release signing, packaging, installation, or updater work was performed.

## 2026-10-05 — T1 foundation source integrated; executable gates still open

The foundation candidate `824a5920f11fb164ebf124ac7da91e402aa3407d` integrates the AppKit/SwiftUI panel, versioned `husky.v1` bindings, bounded typed gRPC client, deterministic fixture server/tests, SwiftPM target graph, pinned `Package.resolved`, and macOS CI workflow. `--fixture-mode --fixture-port 50051` explicitly connects the native panel to the local fixture at `127.0.0.1`; default launch remains unconfigured. The fixture is labeled and is not a production backend. Follow-up fixes preserve the selected conversation across paginated reconnects and await `EndSession` before application termination.

An independent Luna source review passed this exact head after resolving findings on message/event scope, bounded streams and deadlines, cursor sequence validation, partial-message lifecycle, fixture reconnect/history resynchronization, conversation retention across pages, and graceful session shutdown. Strict `swift-format lint --strict`, `git diff --check`, and `swift package dump-package` passed locally on the integrated source. These checks are static evidence only.

Build evidence is older than this candidate: `swift build --cache-path .build/package-cache --scratch-path .build/build` passed at coordinator commit `b4be4d735420c08f7ad68dbd1a957237b70859c9`, before the final T1.2 hardening and T1.7 adapter. A later `swift test` attempt at `4c90ea43ae844938fc6b345c57a5a72613c4f483` stopped during Swift 6 fixture-test compilation (`hasMore_p` generated-field naming and XCTestCase sendability); the source was corrected, but the suite has not been rerun. No build or test pass is claimed for `824a592`, and no CI, TCP listener, native UI, visual-fidelity, release, install, or updater acceptance is established.

Keep T1.1, T1.2, T1.8, T1.9, T1.7, T1.3–T1.6 open until the integrated candidate builds and tests, the real loopback fixture streams through the app, native reference/placement checks pass, CI and exact-head review are current, and the reviewed PR is landed and verified. The tracked `Package.resolved` is present; this supersedes earlier scaffolding notes that resolution was still pending.

## 2026-10-04 — bootstrap correction landed; foundation contract frozen

PR #3 passed renewed independent exact-head review at base `30b1e5a27e105856edc8cdd99b068a2cb428eaa8` / head `e65af86b13e5f1f04fb478b9eb258b593c848b21` and was rebase-merged by GitHub at `91b831bd8dd8b16d3a7434fec38a80370c137dc1`. Landed verification confirmed NOTICE and AGENTS.md are present, tracked public planning files contain no scratch locator or private local path, and LICENSE retains blob `d645695673349e3947e8e5ae42332d0ac3164cd7`.

T1.0 was rebased on that verified base. The canonical schema and contract freeze record API behavior, source ownership, tool and package versions, package license checks, deployment/architecture assumptions, and native placement. The shared build host's one-minute load was above the configured limit of 10, so multi-package builds are deferred; no build result is claimed by preflight.

T1.9 static scaffolding now defines the root SwiftPM target graph, exact direct dependency versions, plugin-driven public protobuf/client/server code generation, and a read-only-permissions macOS CI workflow for build and tests. Package resolution and validation remain open; `Package.resolved` and any CI result are not yet claimed. The standard hosted macOS runner avoids requiring a paid larger runner.

T1.1 UI and T1.2 client/core source handoffs are in coordinator integration commits. Both passed source-scope and whitespace checks. The UI defaults to an explicitly unconfigured backend, with labeled demo data only on request. The protocol lane implements typed events and cursor recovery but could not validate generated RPC namespace symbols without the full plugin build. Load remains over 10, so no Swift build/test or native launch evidence exists yet.

An early independent static source audit before the planned full T1.4 review found actionable protocol, display-restoration and fixture-conformance defects. The saved-display issue was fixed in a scoped UI commit. The protocol owner is separating event acknowledgment from receipt and adding bounded overflow plus contract limit checks; the fixture owner is correcting invalid-ID statuses and replacing sleep-based pagination synchronization. These corrections and all build/runtime behavior remain unverified until integrated tests run. The coordinator's strict formatter pass identified formatting deviations in UI/core; it will be reapplied after source fixes.

## 2026-10-04 — T0.3 bootstrap review remediation

Independent exact-head review of the initial bootstrap change (base `504b574b2ead1718fb2aa64fb969b75ab15d1479`, head `7dc577542570b941d6aaf9f647af1f2596c685b0`) returned BLOCK with three findings: missing repository contributor instructions, an ignored private scratch-path locator in the public plan, and no copyright notice. The reviewer verified that the checked-in Apache LICENSE exactly matched the official text. Remediation adds concise repository instructions and a separate NOTICE naming `Sire Run, Inc.`; LICENSE remains unchanged, and the scratch locator is removed. T0.8 is the required independent exact-head re-review before merge.

T0.7 verification: the delivery-plan parser resolved 24 unique tasks and all dependency references; public-file hygiene search found no scratch locator or private local-path disclosure; all planning-document relative Markdown links resolve; `git diff --check` passes; the repository's Apache LICENSE has no diff; GitHub metadata identifies the repository as public with Apache-2.0 licensing. The new NOTICE contains the supplied holder name. No source implementation was added. These are local verification results, not CI or release evidence.

T0.8 exact-head review passed independently on PR #3 at base `30b1e5a27e105856edc8cdd99b068a2cb428eaa8` and head `b26d2618b783bb538b117f985ceee82ec6b36d8d`. The reviewer authored none of the remediation, confirmed all three finding dispositions, verified equal LICENSE blob IDs and found no blocker. Any later PR head requires renewed exact-head review.

## 2026-10-03 — initial discovery and delivery planning

Confirmed the product boundary, multiple profile/conversation behavior, backend-owned history, common gRPC integration, and independent audio-service boundary through user clarification. The user then requested a plan covering build, public Apache-licensed release, local installation, and automatic self-updates.

Read-only repository discovery found a public empty remote and unborn local main. No pre-existing project source/docs/status was overwritten. Prepared planning artifacts in an isolated external-volume orphan worktree on branch `plan/husky-local-release-20261003`; no remote writes, code build, release, install, or signing-key creation occurred.

The reference HTML/CSS/JS establishes geometry and scene-controlled text tone. Browser URL policy blocked local-reference rendering earlier in discovery; no workaround was attempted. Native fidelity remains unverified.

The project is greenfield, so discovery used the documented manual path. Distribution signing, notarization, updater keys, and CI signing remain execution prerequisites. No application build was run. Machine-specific inventory stays outside public project records.

Inspected upstream Sparkle and gRPC documentation/package requirements. Selected native Swift/AppKit/SwiftUI, the common gRPC API, and Sparkle with signed direct releases as planning defaults. Checked shared cross-project records read-only and found no Husky-specific record to preserve or update. All delivery tasks remain open.

## 2026-10-03 — planning merge preparation

The user requested merging the planning artifacts. Reconfirmed that remote main was absent and prepared a minimal Apache-2.0 LICENSE/ignore-rules baseline so the planning artifacts can use a normal GitHub PR and rebase merge. The license is copied verbatim from the official Apache source. Build outputs, scratch records, and the public project's coordination channel are ignored.

The baseline and exact planning candidate require independent review before publication/merge. Verification covers plan parsing, dependency validity, document links, license integrity, and the public artifact boundary; it does not build the application. Remote SHAs and review/merge disposition belong to the planning PR evidence. No application delivery task, signed release, local install, or automatic update is marked complete by this documentation merge.

Independent review of the first planning candidate identified unnecessary machine-specific discovery details in public records. Removed that inventory while preserving project constraints and release prerequisites. The local workflow compiler lock remains private scratch rather than a portable project artifact. The revised exact head must pass independent review before merge.

## 2026-10-04 — parallel lane and placement refinement

The user confirmed the supplied glass-chat-2 dist as the floating-chat reference, with a frameless transparent window defaulting to bottom left. This supersedes the earlier bottom-right wording. Preserved native implementation, saved-position restoration, and all historical task IDs/status. Split fixture and build scaffolding into T1.8/T1.9, gated independent lanes on a shared contract freeze, and extended integration/review coverage. Later outline expansions must separate independent client, updater and acceptance work while retaining publication/install gates. Planning-only changes; no application build, native visual acceptance, release or installation occurred. Exact review and landing evidence belongs to the planning PR.
# 2026-10-05 — Sizing and diagnostic-bound follow-up

- Source candidate: `c536ce5` (coordinator branch).
- Scaled the original default panel from 560×680 to 448×544 points. Both recognized legacy saved defaults (560×660 and 560×680) normalize to 448×544; other saved frame dimensions pass through unchanged.
- Bubble maximum width, horizontal/vertical padding, and corner radius use the same 0.8 scale. Message font sizes and interaction target dimensions remain unchanged for legibility and accessibility.
- Added bounded diagnostic event text/resume-token handling with focused UTF-8 limit coverage in HuskyCore. The independent worker passed strict formatting and diff checks; integrated tests have not yet run.
- Verification so far: strict Swift formatting for changed app/client/test files and `git diff --check` pass. Full tests/build, native visual/layout and drag/restore checks, and exact-head review remain open. The Mac host load exceeded the documented limit, so build work is paused.
- The first integrated build attempt on `8d748f8` found two stale validator references in the diagnostic-bound change. Both now call the extracted mapper validator (`04e70a0`); formatting and diff checks pass. The build attempt stopped at compile errors before tests, and a rerun is waiting for the shared host load to fall below 10.
- Exact-head review found the 560×660 legacy frame would otherwise restore 16 points shorter than a fresh install. Both legacy defaults now normalize to the same 448×544 target; the reviewer confirmed this correction and the integrated test run passed afterward.
- Sizing correction reviewed at `c536ce5`; both legacy frame variants now match the fresh-install target and custom frames remain unchanged.
- Integrated `swift test --package-path .` passed on `74c9cf3` after correcting the two stale mapper-validator calls. Strict formatting, `swift package dump-package`, and `git diff --check` passed. The build emitted two pre-existing unnecessary-`try` warnings in `HuskyLimitTests.swift`.
- Native fixture window screenshot measured 896×1088 pixels, corresponding to the 448×544-point target at 2×, and the existing conversation text remained readable. Several CUA drag attempts did not change the saved frame, so native movement and restore are still unverified.

## E2 implementation continuation — 2026-10-06

PR #5 rebase-merged the independently reviewed delivery plan at `ec984fb`.
Reviewed candidate `cd5f226` had identical landed content. The E2 source work
adds profile-specific authorization to all RPCs and explicitly cancels local
session teardown so an unresponsive peer cannot block shutdown indefinitely.
Normal startup is being wired to saved connections and accepted-message draft
semantics; static and original fixture demonstrations remain explicit.
Three isolated Luna workers own profile storage, conversation orchestration and
native window lifecycle. Native Mac exemption applies; new full builds/tests
remain held while host load exceeds 10. No new runtime or release claim is made.

## E2 verification checkpoint — 2026-10-06

At `2491d65`, a fresh native `swift test --jobs 2 --cache-path .build/package-cache`
build and all 77 tests passed (58 core, 10 fixture/auth, 9 geometry) under the
shared build lease. The initial run at `0532080` had two failures; endpoint
validation and the paginated canonical-history expectation were corrected,
alongside independently identified replay/create/history/reconnect races.
Both leases were released. Formatting and diff checks passed.

The isolated native proof app launched and wrote a 448×544 autosaved frame,
but CUA returned `cgWindowNotFound`. A read-only session check confirmed the
Mac screen was locked. No unlock was attempted. Saved preferences are not
visible-window, drag, focus, IME, display/Dock or accessibility acceptance.
Owned proof-app and loopback-fixture processes were stopped; no user app or
shared process was stopped. Native acceptance remains blocked on an unlocked
interactive session.

A subsequent additive recovery extension is under verification: authoritative
partial text/revision snapshots and seed propagation through both transport and
controller validators. It prevents guessing state when attaching during an
in-progress message. These changes need a fresh integrated test result and
independent review; the 77-test result does not cover them. PR #6 remains draft.

## Complete E2 source test gate — 2026-10-06

Fresh `swift test --jobs 2 --cache-path .build/package-cache` passed at
`e3b723297b9711cc70380277b14a9f479ef34270`: 65 core + 14 fixture/auth/recovery +
9 geometry = 88 tests. The shared lease was acquired only below load 10 and
released immediately afterward. The app and fixture products compiled in this
run. The additive partial snapshot path is covered over in-process real gRPC,
including seeded replay, missing baseline, revision/cumulative byte rejection,
canonical completion, sequenced asynchronous failure and cursor expiry.

Independent review drove replay-ack, create-retry, pagination/resync, reconnect
state, corrupted-preferences recovery and asynchronous fixture-failure fixes.
Create retry ID/title is retained within a live controller, but not across
application restart; adapter documentation states that limitation. Typed-message
pending ID/payload remains durable per profile/conversation.

Independent Luna source review PASS at `e3b7232` against `ec984fb`, including
all final fixture corrections. Native acceptance remains blocked by the
locked Mac session; no additional CUA attempts or unlock action is pending.
PR #6 remains draft and unmerged. Main's planning PR #5 is landed at `ec984fb`;
the primary checkout was fast-forwarded cleanly to that revision.
