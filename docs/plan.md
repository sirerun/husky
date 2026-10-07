# Husky — native chat, signed releases, local installation, and automatic updates

Current delivery (2026-10-06): PR #4 is merged at `c956db9e68af03ca2b34283948463f721d0c55df`. Foundation source, independent review and source landing are complete. Native acceptance remains open, particularly drag/restore, live display changes, focus/IME and accessibility. Final foundation verification combined the last integrated build with current UI typechecking and 40 unchanged XCTest cases; hosted CI did not run because of account billing. The owner invoked ship again to finish the remaining client and distribution work. Husky is a native Mac project and uses the explicit Mac exemption to workload relocation, retaining load/lease limits.

Client continuation: [PR #6](https://github.com/sirerun/husky/pull/6) contains the complete client source candidate; 88 native automated tests pass at `e3b7232`. It remains unmerged because native acceptance requires an unlocked interactive Mac session. Signed release/install/update tasks remain downstream.

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

### E0 — reviewed project bootstrap (fidelity: executable) → docs/plans/E0.md (11/11)

### E1 — native fidelity proof and API foundation (fidelity: executable) → docs/plans/E1.md (10/11)

### E2 — complete generic chat client (fidelity: executable) → docs/plans/E2.md (11/15)

### E3 — signed release and Sparkle updates (fidelity: outline) → docs/plans/E3.md (0/1)

### E4 — install and prove automatic updates locally (fidelity: outline) → docs/plans/E4.md (0/1)

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
