# Husky — native chat, signed releases, local installation, and automatic updates

Change summary (2026-10-05): integrated candidate `1fd2f084a35629bb32df95035d0408101174def3` now passes `swift test` (8 fixture conformance tests and 23 HuskyCore tests; 31 total). `swift build` passed at implementation candidate `74b10720d5c5964fb444a8fdedff21be6146be07`; subsequent commits changed test code only. Strict Swift formatting lint for tracked app/core/protocol/fixture sources, `git diff --check`, and `swift package dump-package` pass at the current candidate. A native fixture-mode round trip over a verified loopback gRPC connection displayed a backend response and final fixture status; a smoke check exercised scrolling, the full-history fade control, and material selection/restoration. Independent source review passed at `1e0b04f9eccb568b60af2900a31c54bc4b5201b7`; changes since then are test-only. Draft PR #4 is open against `main` at base `91b831bd8dd8b16d3a7434fec38a80370c137dc1`. Its macOS CI run did not start because GitHub reports the account is locked due to a billing issue; the job has zero steps. T1.1 native reference/interaction acceptance, hosted CI, fresh full T1.4 review, merge, landed verification, release, installation, and updater remain open; keep the T1 tasks and dependent gates unchecked.

## 1. Context

Husky is a generic native macOS chat client that floats over desktop apps. It provides a movable stack of glass message bubbles, a composer, scrollable backend-owned history, multiple conversations, and saved backend connection profiles. The selected backend receives typed input and streams text and status events back through a common gRPC API. Audio capture and transcription services operate independently and have no integration dependency on Husky.

The requested delivery includes building the app, releasing it publicly under Apache-2.0, installing it on the local Mac, and proving automatic self-updates. This plan does not execute those actions. See [design](design.md) and [ADR 0001](adr/0001-native-client-and-distribution.md) for architecture and decisions.

Success means: the reference appearance passes native visual comparison; real gRPC requests exercise every chat workflow; an independently reviewed release is published and runs locally; a newer signed release is installed by the automatic updater without losing user state. Passing unit tests alone satisfies none of the release/install/update gates.

## 2. Discovery summary

- `sirerun/husky` is public, with no commits, source, license, CI, design, plan, devlog, ADRs, or indexed code graph at discovery time.
- Manual greenfield discovery found 12 planned use cases: 8 P0 and 4 P1. None is wired.
- The provided glass-chat-2 reference contains HTML/CSS/JS and a demo endpoint. It has no production backend. Its appearance specification is useful, but its transport and demo replies are not Husky implementations.
- The reference uses backdrop blur/transparency, explicit light/dark text tone, and an alpha-mask top fade. Automatic backdrop-luminance sampling is not established reference behavior.
- Local reference rendering was blocked by browser URL policy. Source inspection is complete; visual/native fidelity is unverified. Capture comparison evidence through a supported native/manual route, without circumventing that policy.
- Toolchain, GitHub delivery access, code generation, linting, and build resources must be qualified against pinned requirements before implementation. Discovery does not establish future execution readiness.
- Developer ID signing, notarization authorization, Sparkle signing key, CI signing access, and update hosting are unverified release prerequisites.
- Tasks use explicit Acceptance fields rather than depending on an optional Kazi integration. The empty repository has no code graph to refresh; manual greenfield discovery is appropriate.
- The ancestor's shared Sire documentation was checked read-only: no Husky entry exists in its plan, design, devlog, roadmap, or ADR filenames. This is standalone Husky delivery; these project-specific records do not replace shared cross-repository documentation or modify other services.

### Qualified capabilities

The planning capability resolver selected `baseline` and `delivery`; capability availability must be rechecked at execution. Use `gh` for GitHub, the shell for source/artifact checks, and a qualified computer-use interface for native runtime evidence. No generic app connector, AWS, Cloudflare, or new cloud backend is required. Do not activate plugins globally.

Use the plan parser and local delivery workflow lock as planning tools. Load Swift/AppKit guidance for implementation and team/crew guidance before dispatching workers; load review, merge, release, and landed-verification guidance only when their stages become runnable. Proto code-generation tools must be pinned and qualified in E1, not silently assumed installed.

## 3. Scope and deliverables

| ID | Deliverable | Owner | Acceptance evidence |
|---|---|---|---|
| D0 | Licensed project base | Coordinator | Apache-2.0 license, project records, clean public baseline and known base SHA |
| D1 | Native visual proof and common gRPC contract | Coordinator + workers | Movable transparent panel and real transport fixture with passing native/API checks |
| D2 | Usable generic chat client | Coordinator + workers | Profiles, conversations, history, streaming, recovery, and native acceptance pass |
| D3 | Signed release and automatic updater | Release owner | Public immutable versioned artifacts, valid signatures/notarization, reachable feed |
| D4 | Local installation and update proof | Coordinator | Published release runs locally and automatically upgrades to its signed successor |

Planning defaults: Swift/AppKit/SwiftUI, gRPC Swift 2, Swift Protobuf, Sparkle 2, direct distribution through GitHub Releases, and a static HTTPS appcast deployed through GitHub Pages. These are engineering selections, not claims that integrations already work. Start with macOS 15+ and Apple Silicon; confirm against pinned dependency requirements in E1. Intel support is a later compatibility decision rather than an untested release claim.

In scope: native floating UI; multiple saved profiles with one active backend; multiple backend conversations; common protobuf API and backend implementer documentation; a deterministic real gRPC fixture for conformance; TLS and Keychain credential storage; minimal local preferences/drafts; public source licensing; CI; signed packaging; updater settings and release procedure; install/update acceptance.

Out of scope: microphone permissions, audio playback/transcription, integration with a listener service, a hosted AI backend, arbitrary backend APIs without adapters, browser/mobile/Windows/Linux clients, simultaneous active backends, tool-execution UI, analytics, login-at-startup, and Mac App Store distribution. Backend implementation beyond the conformance fixture belongs to the system integrating with Husky.

Layer coverage: native frontend is required; the common API, generated client, and fixture cover the backend/SDK boundary; infrastructure consists only of CI, artifact hosting, and appcast hosting. There is no server deployment or infrastructure purchase in this plan. A real configured production backend remains a separate integration acceptance target and cannot be claimed from the fixture.

## 4. Checkable work breakdown

Acceptance is stated under each task without requiring optional execution tooling. Dependencies are controller gates. Task rows record verified completion and explicit dependency blocks; discovery evidence alone does not mark delivery work complete. Estimates are work sessions, not calendar commitments.

### E0 — reviewed project bootstrap (fidelity: executable)

Acceptance: a reviewed docs/license-only base exists on remote main so normal code PRs can start; public records contain no private machine information.

- [x] T0.0 Preflight scope, worktree, and empty-remote bootstrap  Owner: coordinator  Est: 1 session  kind: agent stage: preflight  deps: []  delivers: [D0]
  - Acceptance: re-read current refs/status and project channel; verify external storage; record source-asset rights and compatibility assumptions; verify remote has no competing base or work. Record missing signing prerequisites without blocking local UI discovery. Define the docs-only genesis exception below.
- [x] T0.1 Prepare the docs/license-only bootstrap candidate  Owner: bootstrap worker  Est: 1 session  kind: agent stage: implement  deps: [T0.0]  delivers: [D0]
  - Acceptance: candidate contains project planning records, the official Apache-2.0 LICENSE, minimal project instructions, and ignore rules for scratch, build artifacts, and the project channel. No application code or copied unqualified assets are included. Set an appropriate project copyright notice; preserve any required third-party notices.
- [x] T0.2 Verify bootstrap content and public hygiene  Owner: coordinator  Est: 1 session  kind: agent stage: verify  deps: [T0.1]  delivers: [D0]
  - Acceptance: license text matches the official source; plan dependencies and links resolve; proposed choices remain labeled; public diff has no secrets, personal paths, hostnames, private endpoints, or private project material. Stage only intended durable artifacts; scratch is excluded.
- [x] T0.3 Independent content review of T0.1  Owner: independent reviewer  Est: 1 session  kind: agent stage: review  deps: [T0.2]  delivers: [D0]
  - Acceptance: reviewer identity, exact base/head SHA, scope, findings, and dispositions are recorded. Initial independent review of PR #1 returned BLOCK with findings T03-01 through T03-03. Remediation, affected verification, and an exact-head re-review are tracked in T0.6–T0.8; the findings block any further bootstrap merge until T0.8 passes.
- [x] T0.4 Establish remote main with the reviewed docs-only genesis  Owner: coordinator  Est: 1 session  kind: agent stage: merge  deps: [T0.3]  delivers: [D0]
  - Acceptance: recheck the remote is still empty and publish exactly the reviewed docs-only root using a non-forced push. Record remote main SHA. This explicit bootstrap exception is necessary because GitHub cannot rebase-merge a PR without a base branch; it never includes source implementation. If a base now exists, reconcile and use a normal reviewed rebase PR instead.
- [x] T0.5 Verify the landed project base  Owner: coordinator  Est: 1 session  kind: agent stage: verify-landed  deps: [T0.4]  delivers: [D0]
  - Acceptance: remote main equals the recorded reviewed revision, license is discoverable, intended docs are present, and no scratch/private material landed. E1 can branch from this SHA.

The initial T0.3 review found that the merged bootstrap did not meet all T0.1/T0.2 acceptance criteria. Its corrective delivery is explicit:

- [x] T0.6 Remediate T03-01 through T03-03  Owner: coordinator  Est: 1 session  kind: agent stage: implement  deps: [T0.3]  delivers: [D0]
  - Acceptance: add concise project instructions and attribution without editing the official Apache license text; remove the private scratch-manifest locator from public documentation. Preserve the docs-only boundary and all authored project decisions.
- [x] T0.7 Verify T0.6 bootstrap remediation  Owner: coordinator  Est: 1 session  kind: agent stage: verify  deps: [T0.6]  delivers: [D0]
  - Acceptance: the copyright notice names the owner-selected project holder; LICENSE remains byte-for-byte identical to the official Apache-2.0 text; project instructions and plan/design links resolve; no ignored scratch path, private local path, secret, endpoint, or implementation asset is added.
- [x] T0.8 Independent exact-head review of T0.6 remediation  Owner: independent reviewer  Est: 1 session  kind: agent stage: review  deps: [T0.7]  delivers: [D0]
  - Acceptance: a fresh reviewer authored none of the candidate, records the correction PR URL, exact base/head SHA, all T03 finding dispositions, public hygiene and license evidence; no blocking findings remain. PASS by independent GPT-6-Luna reviewer on PR #3 at base `30b1e5a27e105856edc8cdd99b068a2cb428eaa8`, head `b26d2618b783bb538b117f985ceee82ec6b36d8d`; all three findings resolved, Apache LICENSE blob unchanged, and no blocker.
- [x] T0.9 Rebase-merge the bootstrap correction PR  Owner: coordinator  Est: 1 session  kind: agent stage: merge  deps: [T0.8]  delivers: [D0]
  - Acceptance: merge the exact approved correction PR through GitHub rebase and record the landed SHA. No force push or stale review is used.
- [x] T0.10 Verify the corrected project base  Owner: coordinator  Est: 1 session  kind: agent stage: verify-landed  deps: [T0.9]  delivers: [D0]
  - Acceptance: remote main contains the reviewed project instructions and notice, the public plan has no scratch locator, Apache license bytes are unchanged, and the tree contains no T03 blocker. T1.0 may proceed from this verified base. PR #3 rebase-merged at `91b831bd8dd8b16d3a7434fec38a80370c137dc1`; remote main advances beyond the exact reviewed PR head, required files are present, hygiene search is clear, and LICENSE blob remains `d645695673349e3947e8e5ae42332d0ac3164cd7`.

### E1 — native fidelity proof and API foundation (fidelity: executable)

Acceptance: a native panel demonstrates the requested appearance and behavior, and a pinned protobuf contract/client/fixture communicate over real gRPC. This is a foundation milestone, not a usable release.

- [x] T1.0 Preflight native and transport foundation  Owner: coordinator  Est: 1 session  kind: agent stage: preflight  deps: [T0.5, T0.10]  delivers: [D1]
  - Acceptance: exact base/ownership recorded; dependency versions, macOS deployment target, architecture, bundle ID availability, proto generation, and package licenses qualified. CI check definitions and native evidence route chosen. External build caches and shared lease procedure verified before builds. Freeze the shell/core interface, protobuf wire contract and generated-binding baseline, event model, error semantics, target/source paths, and file ownership before parallel workers edit. The coordinator prepares only the minimal shared contract scaffold in this gate; T1.4 explicitly reviews it. Record a versioned contract snapshot so the client and fixture lanes start independently without guessing APIs.
  - Evidence: preflight rebased on verified base `91b831bd8dd8b16d3a7434fec38a80370c137dc1`. Contract snapshot and canonical `husky.v1` schema are in `docs/contracts/husky-v1-foundation-freeze.md` and `Packages/HuskyProtocol/Sources/HuskyProtocol/v1/husky.proto`; source boundaries and bottom-left native placement align with accepted design. Toolchain, dependency versions/licenses, proto generation route, ARM64/macOS 15 minimum, bundle ID caveat, external volume, and build lease were qualified. Host load exceeded 10 at this checkpoint, so multi-package builds remain held until the load gate clears; no build evidence is claimed here.
- [ ] T1.1 Implement native floating-panel proof  Owner: UI worker  Est: 2–3 sessions  kind: agent stage: implement  deps: [T1.0]  verifies: [UC-H01, UC-H02, UC-H03, UC-H08]  delivers: [D1]
  - Acceptance: borderless transparent AppKit panel hosts SwiftUI bubbles/composer; whole stack drags; first launch defaults to the bottom left of the active display’s visible frame, inset from the Dock and screen edges; no title bar, frame, or opaque rectangular window background is visible; view scrolls up/down; reference geometry, alternating alignment, fade, and appearance are preserved. Prototype compares native backdrop materials with custom tint/border layers. No network, microphone, or fake production assistant is hidden in the UI.
- [ ] T1.2 Implement the common API and generated transport client  Owner: protocol worker  Est: 2–3 sessions  kind: agent stage: implement  deps: [T1.0]  verifies: [UC-H04, UC-H05, UC-H06, UC-H07, UC-H09]  delivers: [D1]
  - Acceptance: `husky.v1` protobuf contract supports capabilities/version negotiation, conversation list/create, cursor-paginated authoritative history, typed-message submission, unsolicited backend events, text deltas/completion/status, cancellation, and recovery. Stable conversation/message/request IDs, sequence/cursor semantics, duplicate-send handling, partial replacement, history/live reconciliation, errors, and limits are specified. The transport client conforms to the frozen T1.0 contract; fixture implementation belongs to T1.8. Contract changes return to the coordinator before dependent lanes proceed.
- [ ] T1.8 Implement independent real-gRPC conformance fixture  Owner: fixture worker  Est: 2 sessions  kind: agent stage: implement  deps: [T1.0]  verifies: [UC-H04, UC-H05, UC-H06, UC-H07, UC-H09]  delivers: [D1]
  - Acceptance: own `Tools/HuskyFixture/` and its conformance tests; implement the frozen wire contract with deterministic streaming, pagination, unsolicited events, cancellation, duplicate submission, and reconnect cases. Use pinned generated bindings from T1.0, never worker-local invented protocol shapes. Clearly label fixture responses; no production AI backend claim.
- [ ] T1.9 Implement foundation build and CI scaffolding  Owner: coordinator  Est: 1 session  kind: agent stage: implement  deps: [T1.0]  delivers: [D1]
  - Acceptance: own root project/package/CI configuration, pinned generation entry points and app target assembly; publish stable target and source-path contracts at T1.0 so workers need not edit shared configuration. Static configuration work overlaps all three worker lanes; multi-package builds still obey the shared lease and host-load gates.
- [ ] T1.7 Implement foundation integration and build/CI configuration  Owner: coordinator  Est: 1 session  kind: agent stage: implement  deps: [T1.1, T1.2, T1.8, T1.9]  verifies: [UC-H01, UC-H07]  delivers: [D1]
  - Acceptance: connect the native proof to the labeled real gRPC fixture through the agreed core interface; add reproducible app/project/package configuration, pinned code-generation entry points, and scoped CI checks. Show an actual streamed response/status in the native proof without representing the fixture as production. Root configuration ownership stays with the coordinator. This is code implementation and is included in T1.4 review coverage.
- [ ] T1.3 Verify T1.1, T1.2, T1.8, T1.9, and T1.7  Owner: coordinator  Est: 2 sessions  kind: agent stage: verify  deps: [T1.7]  verifies: [UC-H01, UC-H02, UC-H03, UC-H04, UC-H05, UC-H06, UC-H07, UC-H08, UC-H09]  delivers: [D1]
  - Acceptance: run targeted Swift tests, format/lint and CI checks; real gRPC tests cover success plus cancellation/reconnect/error ordering. Native XCUITest/manual evidence covers scrolling, dragging, text input/focus, IME, reference comparison over light/dark/busy backgrounds, visible desktop through unused transparent margins, absence of window chrome, fresh-preferences bottom-left launch, saved-position restore, monitor/Dock changes, and Reduce Transparency/Motion. Report native blur differences; do not silently weaken the user's visual requirement. Integrate through agreed core interfaces. No browser-test requirement is invented for a native UI.
- [ ] T1.4 Independent code review of T1.1, T1.2, T1.8, T1.9, and T1.7 candidate  Owner: independent reviewer  Est: 1 session  kind: agent stage: review  deps: [T1.3]  delivers: [D1]
  - Acceptance: reviewer authored none of the covered code; report records PR URL, exact base/head SHA, the T1.0 shared contract scaffold and all five implementation scopes (T1.1, T1.2, T1.8, T1.9, T1.7), tests/native evidence, findings, and disposition. Track accepted fixes, rerun affected verification, and reopen this gate against the changed head.
- [ ] T1.5 Rebase-merge the exact reviewed foundation PR  Owner: coordinator  Est: 1 session  kind: agent stage: merge  deps: [T1.4]  delivers: [D1]
  - Acceptance: required CI and review are current for the exact head; merge through `gh` using GitHub rebase and record landed SHA. Never force-push main or reuse stale review evidence.
- [ ] T1.6 Verify the landed foundation  Owner: coordinator  Est: 1 session  kind: agent stage: verify-landed  deps: [T1.5]  delivers: [D1]
  - Acceptance: landed revision passes the targeted native/API checks and source comparison; report fixture-only limitations and open fidelity issues. Record the final interface, dependency pins, OS target, and artifact layout so subsequent epics can be decomposed accurately.

### E2 — complete generic chat client (fidelity: outline)

Acceptance: all D2 workflows work against the conformance backend: saved connection profiles, credential handling, one active backend, conversation switch/create, history pagination, typed input, streamed replies/status, unsolicited backend events, cancellation, reconnect, and visible connection/error state. No message history is owned by Husky. Profile/conversation switches detach old streams, isolate state, retain drafts safely, and discard late events from previous connections. Native panel position restores, remains reachable after display changes, hides/summons reliably, and does not steal focus on incoming events. Older history never jumps when live updates arrive. Backend setup documentation enables an independent adapter implementation.

- [ ] T2.0 PLAN: expand E2 from the proven native/API foundation  Owner: coordinator  Est: 1 session  kind: plan  deps: [T1.6]  delivers: [D2 executable delivery tasks]
  - Acceptance: use current landed interfaces/evidence to create owned implementation slices and paired changed-behavior/API/native checks; include first-class preflight, verify, independent review, rebase merge, and landed-verification rows. Cover UC-H01–UC-H10, dependency references, and complete wiring. Flip only E2 to executable fidelity.

### E3 — signed release and Sparkle updates (fidelity: outline)

Acceptance: D3 includes Apache-2.0 source, dependency license notices, build instructions and adapter docs, CI, an installable Developer ID-signed/notarized/stapled app package, checksums, versioned GitHub Releases, and a stable HTTPS Sparkle appcast. Bundled updater helpers are signed correctly. Sparkle update archives have EdDSA signatures; signing credentials/keys stay in protected storage. Appcast publication follows successful artifact upload and validation. Tags and versioned binaries are immutable. GitHub Pages availability/permissions must be proven before embedding its feed URL; use no billable/new hosting silently.

Automatic updates check/download in the background and install at a safe idle/quit/relaunch boundary, preserving drafts and profile/position preferences and avoiding interruption of an active stream. Provide Check for Updates and an opt-out setting. Qualified Sparkle defaults, timing, entitlement requirements, signed-feed support, refusal of invalid signatures, and minimum OS/architecture selection are tested against the pinned version. User-controlled update preferences persist.

- [ ] T3.0 PLAN: expand E3 with the known app and packaging interfaces  Owner: coordinator  Est: 1 session  kind: plan  deps: [T1.6, T2.0]  delivers: [D3 executable delivery tasks]
  - Acceptance: add dependency-linked source/workflow implementation, verification, independent exact-head review, rebase merge, landed checks, artifact creation/release/publication, and remote feed verification tasks. Release gates depend on E2 landed acceptance. Create named credential-readiness tasks for Developer ID, notarization authorization, Sparkle signing key, and protected CI access; identify any human provisioning prerequisite without exposing secrets. Define version/build-number policy and at least two genuine reviewed release revisions for E4. No unsigned artifact satisfies the public release gate.

### E4 — install and prove automatic updates locally (fidelity: outline)

Acceptance: install the published signed release locally in `/Applications/Husky.app` if accessible, otherwise the user's Applications directory with the actual path reported. Preserve any pre-existing app/state; stop for an ownership conflict rather than overwriting unrelated work. Verify signatures/notarization/Gatekeeper and launch the downloaded artifact, not a developer build. Exercise profiles, backend connection, conversations, scroll, drag, and streaming. Then publish a legitimate reviewed successor release and observe Sparkle discover/download/install it automatically from the public feed. The reopened app reports the successor build; profiles, geometry, drafts, and backend history access survive. Manual replacement or Check for Updates alone is insufficient proof of automatic updates.

Negative updater tests use an isolated fixture/feed: tampered archives, unavailable feed/network, no-new-version, incompatible target, and interrupted downloads fail safely without damaging the installed app. A relaunch/connection recovery check proves that active-stream deferral works. Keep artifact checksums, tag/source SHAs, release/feed URLs, installed-before/after versions, native captures, and observed timings in the devlog/evidence record. Local success is not proof on untested Macs.

- [ ] T4.0 PLAN: expand E4 against the release/install/update contracts  Owner: coordinator  Est: 1 session  kind: plan  deps: [T2.0, T3.0]  delivers: [D4 executable acceptance tasks]
  - Acceptance: create install preflight, published-artifact installation, native verification, automatic successor-update verification, and independent acceptance review tasks gated by E3 release/artifact/feed evidence. Any code fix acquires its own verify/review/merge/landed chain. Specify exact artifact identity, safe installation target, auto-update timing, state-survival checks, failure fixtures, and evidence fields before running the installer. Flip only E4 to executable fidelity.

## 5. Parallel work and waves

One coordinator owns contracts, integration, stage transitions, and final evidence. Execution uses GPT-6-Luna workers where safe, with isolated external-SSD worktrees and explicit file ownership; load team/crew guidance first. Respect the active harness limit of three workers plus the coordinator. The same shell/API agreement is finalized before implementation dispatch; independent review uses a fresh reviewer that authored neither scope.

| Wave | Work | Workers / ownership |
|---|---|---|
| 0 | T0.0–T0.5, then T0.6–T0.10 for accepted review findings | Bootstrap work and remediation are verified and independently reviewed before their respective rebase merges; coordinator owns the merge and landed checks |
| 1 | T1.0 | Coordinator qualifies tools and freezes shared interfaces |
| 2 | T1.1, T1.2, T1.8 concurrently; coordinator overlaps T1.9 | UI owns `App/Husky/`; transport owns `Packages/HuskyProtocol/` except the coordinator-frozen schema and `Packages/HuskyCore/`; fixture owns `Tools/HuskyFixture/`; coordinator alone owns root project/package/CI files and the generator config. Frozen protocol changes require coordinator reconciliation. |
| 3 | T1.7, then T1.3–T1.6 | Integrate all four scopes; verify; fresh independent reviewer covers T1.0 scaffold and every implementation row; exact-head merge and landed verification stay sequential. Release completed workers before assigning the reviewer. |
| 4 | T2.0, then T3.0, then T4.0 | Retain stable planning IDs; expand once contract evidence exists. Each expansion must maximize independent executable lanes as described below. |

Maximum concurrency is three workers plus the coordinator, not unlimited builds. Each worker receives an isolated external-SSD worktree, exact base/contract revision, exclusive paths, acceptance criteria, and handoff evidence. Work stealing is permitted only after ownership is released and the coordinator assigns the next ready task. Do not overlap writes to `docs/plan.md`; use the plan claim and reconcile current content.

Expansion requirements: T2.0 separates (a) profile/Keychain/preferences core, (b) conversation/history/recovery core, and (c) UI composition/accessibility into three ownership-disjoint implementation lanes after a shared interface freeze. Coordinator owns root configuration and integration. Assign concrete subdirectories before dispatch, since these scopes otherwise overlap `HuskyCore` and `App/Husky`. Give each lane its own targeted verification and give the integrated candidate independent review, merge and landed gates. T3.0 separates updater integration, release automation, and signing/feed prerequisite qualification; prerequisite discovery may overlap client implementation once its own preflight is satisfied, but publishing waits for reviewed landed client and updater code, signing authority and artifact checks. T4.0 separates native acceptance preparation and isolated negative-update fixtures from publication-dependent installation and automatic-update observation. These are required decompositions for the outline planning rows, not authorization to dispatch unexpanded work. Signing delays must not block unrelated local client lanes.

Never dispatch an outline's implementation until its planning task creates executable rows. The later planning tasks produce plans, not release readiness; their generated implementation/release/install gates must depend on actual prior verification and landed/artifact tasks. Do not treat completion of T3.0 as a published release.

## 6. Milestones

| Milestone | Exit criterion | Dependency |
|---|---|---|
| M0: project base | Public reviewed docs/license base, project instructions and copyright notice are present; the bootstrap review findings are resolved | T0.10 |
| M1: foundation | Native fidelity and real gRPC contract proof landed | T1.6 |
| M2: usable client | D2 end-to-end workflows pass on landed source | E2 generated landed-verification gate |
| M3: distributable release | D3 signed artifact/feed remotely verified | E3 generated release verification gate |
| M4: installed and updating | D4 published artifact launches and upgrades automatically | E4 generated independent acceptance gate |

Do not invent dates before M1 evidence. D0/D1 estimates cover discovery and focused implementation only; signing/provider provisioning is external elapsed time.

## 7. Risks and open prerequisites

| ID | Risk / gap | Response |
|---|---|---|
| R1 | Native materials may differ from the CSS reference | Prototype first; compare screenshots and scroll/focus behavior; record unresolved fidelity rather than declaring equivalence |
| R2 | Distribution signing and notarization unqualified | E3 release blocked until a suitable protected signing identity and notarization authorization are verified; development builds remain separately labeled |
| R3 | Feed/key/hosting not provisioned | Qualify GitHub Pages/Actions permissions and protected signing storage; sign and verify artifacts before feed publication |
| R4 | Generic backends differ in capabilities/history/event semantics | Publish a versioned contract, negotiation/error semantics, and conformance tests; reject incompatible servers visibly |
| R5 | No real backend integration selected | Release can prove the generic client with a labeled fixture; actual backend compatibility requires independent adapter evidence |
| R6 | Retry/live-history reconciliation duplicates or loses messages | Stable IDs, idempotency, cursors, snapshot boundary and gap recovery; real transport tests for interruption and concurrent history fetch |
| R7 | Update/relaunch loses drafts or disrupts chat | Persist drafts locally, defer install while busy, verify state survival and reconnection through a real successor update |
| R8 | Empty repository and concurrent work | Docs-only reviewed genesis, recheck refs before publication, isolate every worker, retain all authored records and claims |
| R9 | OS/architecture scope could exceed evidence | Qualify pinned dependencies; start with macOS 15+/Apple Silicon; document tested matrix and do not claim Intel/older-OS support |

## 8. Operating procedure

The plan skill delivers the planning artifact through validation, independent review, rebase merge and landed verification; it does not execute application tasks. Execute via `$ship` from this worktree when requested. User authorization to plan releases/install is not evidence that they occurred.

For every code candidate: preflight → implement → targeted/native/API verification → independent exact-head review → required CI → GitHub rebase merge → landed verification. Release publication and local installation are additional required gates in this scope. Review findings create tracked fixes and renew affected checks/review. Record base/head/landed SHAs and evidence at stage boundaries. Do not erase completed tasks or old evidence during expansion.

Create new task/worker worktrees, caches, DerivedData, SwiftPM caches, generated packages, archives, and disposable profiles on the verified external build volume. Use task-specific environment variables and build output arguments. Check load before heavy multi-package builds; hold above one-minute load 10. Use the canonical shared build lease, verify WON, retain its token, and release immediately after the build through the helper's current API. No more than two heavy lanes per project. Do not repurpose HOME.

Because this is a public repository, ignore the append-only project channel and scratch outputs. Read the channel when present; append sanitized coordination events only when needed. Stable architecture belongs in design.md, decisions in ADRs, and observed/debug/release/install facts in devlog.md. Credentials never belong in these files or workflow logs.

## 9. Progress log

- 2026-10-04: refined E1 to three independent worker lanes plus coordinator scaffolding after a shared contract freeze. Added T1.8/T1.9 without renumbering historical IDs. Confirmed frameless transparent chat and bottom-left initial placement from the glass-chat-2 dist reference; later outline expansions must separate ready work from signing/publication gates. No application task is completed by this refinement.
- 2026-10-04: independent T0.3 reviewer examined PR #1 at base `504b574b2ead1718fb2aa64fb969b75ab15d1479` / head `7dc577542570b941d6aaf9f647af1f2596c685b0` and returned BLOCK. Stable findings: T03-01 missing project instructions, T03-02 public ignored scratch-manifest locator, T03-03 missing project copyright notice. Reviewer confirmed Apache LICENSE was byte-identical to upstream and found no other public-boundary issue. T0.6–T0.10 track remediation through re-review and landed verification; T1.0 now depends on T0.10.
- 2026-10-04: fresh independent GPT-6-Luna reviewer passed PR #3 at base `30b1e5a27e105856edc8cdd99b068a2cb428eaa8` / head `b26d2618b783bb538b117f985ceee82ec6b36d8d`. T03-01 through T03-03 are resolved; `LICENSE` base/head blob IDs match, and plan IDs/dependencies and public hygiene are clear. This review is exact to that PR head; rerun it if the PR head changes.
- 2026-10-04: PR #3's updated exact head `e65af86b13e5f1f04fb478b9eb258b593c848b21` passed renewed independent review, then GitHub rebase-merged it at `91b831bd8dd8b16d3a7434fec38a80370c137dc1`. T0.10 confirmed the landed NOTICE/instructions, clean public-hygiene search, and unchanged LICENSE blob. T1.0 was rebased on that main and froze the native/transport contract. Shared host load exceeded the configured build gate; builds are deferred until it clears.
- 2026-10-04: began T1.9 coordinator scaffolding from the frozen target map: root SwiftPM products/targets, exact direct dependency versions, gRPC protobuf generator configuration, and macOS CI build/test workflow. Package resolution, manifest validation, and builds remain pending; host load is over the gate, so T1.9 is not marked complete.
- 2026-10-04: T1.1 source handoff committed at `4a32e813517f0f12fc32163d896d5d90e9eba130` (UI files only, static checks passed) and T1.2 at `f09e9247dc799e34447e1b0e30487ef95c6b2c14` (core client/cursor/tests only, static checks passed); both are cherry-picked into the coordinator integration worktree. UI runtime/native evidence and Swift tests/build remain pending. The protocol worker reports the generated service namespace was inferred before plugin validation. Current host load is above 10; defer all builds until the gate clears.
- 2026-10-04: early independent static audit of integrated T1.1/T1.2/T1.8 sources found issues before acceptance: premature cursor acknowledgment; unbounded stream buffer; missing upper capability and incoming-body checks; saved panel placement clamped against the wrong display; fixture empty IDs mapped to the wrong status; and sleep-based pagination synchronization. The UI owner fixed saved-display restoration in `30e11f7af8903987bdc0676d86d86167b45ed581`; protocol and fixture owners are addressing their findings. Keep T1.1, T1.2, and T1.8 open until fixes land and affected checks pass. A strict formatter pass also found UI/core style deviations; format after lane fixes to avoid conflicting edits.

- 2026-10-03: created this initial plan and architecture/decision records after product clarification and read-only environment discovery. All delivery tasks remain open. Signing and exact native visual equivalence remain unverified.

## 10. Handoff notes

The initial planning branch is `plan/husky-local-release-20261003`; it was created as an isolated orphan worktree because the repository was empty. At the end of planning, no branch had been published and the main checkout was untouched. The subsequent docs-merge task prepares an Apache-2.0/license-ignore baseline and normal planning PR; its reviewed/landed SHAs are recorded in GitHub delivery evidence. Reconcile the current remote main and local checkout before execution rather than repeating an already-completed bootstrap. Do not merge unrelated project work. The application delivery tasks remain open.

The original reference lives outside this repository; the private absolute locator belongs only in local scratch. Public docs use the reference name and sanitized geometry. Preserve its authored material and qualify rights before copying assets; use native SF Symbols where appropriate. Browser policy denial must not be bypassed.

Open prerequisites are distribution signing/notarization availability, updater key ownership, CI/release/feed permissions, and later real backend adapter evidence. Proposed bundle ID and exact pinned versions are E1 preflight outputs. Automatic install defaults and public hosting must be qualified against the chosen Sparkle version before release. No additional cloud purchase is assumed.

## 11. References

- [Sparkle setup, signing, and appcasts](https://sparkle-project.org/documentation/)
- [Sparkle updater customization](https://sparkle-project.org/documentation/customization/)
- [gRPC Swift 2](https://github.com/grpc/grpc-swift-2)
- [Swift NIO gRPC transport](https://github.com/grpc/grpc-swift-nio-transport)
- [AppKit floating panels](https://developer.apple.com/documentation/appkit/nspanel)
- [Behind-window visual effects](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Official Apache-2.0 text](https://www.apache.org/licenses/LICENSE-2.0.txt)
- [Applying Apache-2.0](https://www.apache.org/legal/apply-license)
