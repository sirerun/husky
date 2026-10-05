# Husky devlog

## 2026-10-05 — T1 foundation source integrated; executable gates still open

The foundation candidate `33f53dd08a0ba1cdcedd262f08e6b3975d590163` integrates the AppKit/SwiftUI panel, versioned `husky.v1` bindings, bounded typed gRPC client, deterministic fixture server/tests, SwiftPM target graph, pinned `Package.resolved`, and macOS CI workflow. `--fixture-mode --fixture-port 50051` explicitly connects the native panel to the local fixture at `127.0.0.1`; default launch remains unconfigured. The fixture is labeled and is not a production backend.

An independent Luna source review passed this exact head after resolving findings on message/event scope, bounded streams and deadlines, cursor sequence validation, partial-message lifecycle, and fixture reconnect/history resynchronization. Strict `swift-format lint --strict`, `git diff --check`, and `swift package dump-package` passed locally at this candidate. These checks are static evidence only.

Build evidence is older than this candidate: `swift build --cache-path .build/package-cache --scratch-path .build/build` passed at coordinator commit `b4be4d735420c08f7ad68dbd1a957237b70859c9`, before the final T1.2 hardening and T1.7 adapter. A later `swift test` attempt at `4c90ea43ae844938fc6b345c57a5a72613c4f483` stopped during Swift 6 fixture-test compilation (`hasMore_p` generated-field naming and XCTestCase sendability); the source was corrected, but the suite has not been rerun. No build or test pass is claimed for `33f53dd`, and no CI, TCP listener, native UI, visual-fidelity, release, install, or updater acceptance is established.

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
