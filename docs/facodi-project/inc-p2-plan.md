# INC-P2: Canonical Execution Cutover

Status: execution authorized, bounded text slice under validation; full P2 cutover and
production rollout are not complete. Prerequisite: reviewed INC-P1 commits and exact-head CI. P1 owner is
API PR26, `3891e749c05008344cca26ad099ead26ef344c6a`.

## Execution Plan: 2026-10-08

The owner requested planning followed by autonomous implementation and necessary
promotion/merges. Preserve the invariants below and require the promotion gates;
authorization does not waive tests, backup pairing or target/image verification.
Starting deployment is `3d4caf6`, with API `ee86ea6` and Learning `1a4bb09`.
Read-only approved connector inspection confirmed the FACODI target and installed
Project `19.0.1.0.0`, API `19.0.3.3.0`, Learning `19.0.2.2.0`. This does not
identify the productive image or prove the private canary.

1. Integrate the reviewed architecture PR271 after verifying its exact-head CI
  and compatibility with current main. Complete P1 operational verification
  through the approved live workflow, not by assuming merge means deployment.
2. Implement P2 atomic acceptance in API: an initially disabled canonical route,
  explicit managed company/Website workspace and immutable accepted executor.
  Test disabled routing, failed workspace authorization, replay after routing
  changes, rollback and absence of per-run Projects/technical subtasks.
3. Implement the durable Supabase contract in its independent owner: stable task
  key/job UUID, transactional claim/lease/checkpoints, recovery and bounded
  authenticated receipt transport. Test real database races and restart/crash
  windows before integrating API dispatch and callbacks. Never repurpose old
  provider identities or call remote processing before intake commits.
4. Cut over only newly accepted Learning jobs through the shared API boundary.
  Preserve native content/review, existing providers and all historical work.
  Reconcile receipts monotonically and project only human-actionable events.
5. Run native suites, provider database/security/crash tests, full integration,
  install/two upgrades/history, desktop/mobile browser and paired restore.
  Publish owner PRs and exact pins in dependency order; merge only green heads.
6. Promote through the existing resource and migration gate after target,
  applicable paired restore point, secrets and actual image identity are
  verified. Use a new private unpublished canary, then activate a bounded
  cohort. Disable new intake expansion on rollback but continue reconciliation
  of already accepted jobs. Record observed results, not inferred completion.
7. Reduce duplicate Learning workflow only after parity (P4), following the P3
  policy gate where applicable. P3 automatic decisions/publication, P5 Portal
  expansion and P6 AI retirement retain their own acceptance boundaries; no
  silent publication or AI uninstall is part of the initial P2 cutover.

Current external preflight: the user restored Supabase MCP access. Read-only
inspection verified `https://bhfywztfyidvrlarebmg.supabase.co`, the existing
processing table with RLS, migration history and zero security advisories.
CLI authentication was restored by the owner; remote access was already verified
through MCP. The owner confirmed that main automatically deploys through the
existing Coolify resource; no generic extra deployment permission is required.
Productive image identity remains unverified. The previously confirmed paired
backup must be checked for applicability to the final schema rollout, not
described as unavailable. No ad hoc RPC client, secret prompt through the assistant, target
substitution or production fallback is permitted. Remote migration still
requires the exact validated source and promotion gates, not tool availability.

Rejected alternatives: a simultaneous replacement of all executors would lose
accepted-provider recovery; retrofitting old runs violates passive history;
keeping technical execution in both Odoo and Supabase duplicates authority.
The first falsifiable check is native replay after the intake route is disabled:
the accepted executor and canonical task must remain identical, without a new
Project, task or remote job.

### Current Slice Evidence

Versioned cancellation continuation: API
`7205bc8b4e5ad25fb08958b20ef6045e565a5a35`, Learning
`32056a3745ccc137f7e7b6f19fca1d6b0a85dc2f` (patch `19.0.2.2.2`), Supabase
`c42ccdc36fe2afca3ac8cef53a9871086fc17e29`. Local gates passed: 47 native
API security tests, 104 pure API tests, 426 native Learning tests, 18 Supabase
Python checks including 13 native database tests, and 27 Deno tests plus frozen
typecheck. Both migrations installed cleanly in a new disposable database;
schema lint and security advisors found no issues. The clean-pin native harness
passed independent Project tests/races, API 47, consumers 19, two upgrades,
history preservation, HTTP role/boundary tests, reviewed native publication,
restart and the unpublished canonical cancellation probe. Learning CI initially
used an older API pin without Project fields; its successor pins the accepted API
and packages the native Project sibling. The repaired CI image passed a clean
19-test consumer install locally. Exact successor CI is pending.

Canonical cancel accepts one immutable versioned local intent without precommit
network. It immediately blocks publication and preserves human task fields.
The committed dispatcher recovers a lost job binding and retries the same scoped
command UUID until its exact acknowledgement. Supabase preserves the prior
receipt in an append-only service-only audit, archives the message and fences
the worker atomically. Real tests cover concurrent finish/cancel and twenty
command replays, rollback, identity/version conflicts and residual messages.
Already active external I/O is not interrupted, but cannot checkpoint or finish.
Learning records a late acknowledged real attempt exactly once; acceptance alone
does not invent an attempt. The composed probe retains immutable historical
results after withdrawal. Legacy commands and accepted source data are unchanged.
Versioned retry/input and full source/activation parity are still required;
this is not complete P2 or production acceptance.

Catalog continuation candidates: API `9e80f0088ff008db5dc6e166b90cd3a234012cec`,
Learning `60d223fda80544af7e833f394a91e4f2a29e24bd` (patch `19.0.2.2.1`), and
Supabase `5102e431fa8d672ec5fcbd5c72a39f759ac4124e`. Local API tests: 44 native,
112 pure and one historical skip. Learning: 425 native tests. Supabase: 13 Python
tests (eight native database) and 26 Deno tests/typecheck. Deployment: 65 contracts.
The actual authenticated endpoint/native SQL test now carries a catalog; the
composed unpublished probe preserves exact proposals in both API metadata and
the existing immutable Learning result. Exact successor CI remains required.

The complete authorized catalog is frozen in dispatch, within the 60000-byte
ASCII JSON wire budget. Supabase verifies company/Website scope and the existing
Python sorted-ASCII-JSON SHA-256 before enqueue/acquisition/payment. Native golden
fixtures cover Unicode, astral characters and control escaping. Mapping preserves
deterministic-v2 scores, threshold, ties, top five and unmatched concepts; evidence
terms have stable sorting rather than Python's unordered set iteration. Mapping
and enriched-document identity share the saved analysis checkpoint. A mismatched
recovery checkpoint fails for native human review without a new paid call.
API accepts only matching snapshots and proposed targets; old immutable requests
without catalog and old ASCII receipt encoding remain replay-compatible.
No historical editorial result is rewritten and no proposal is auto-approved.

Verified preceding bounded-worker release, not CI acceptance of these successors:

- Continuation candidates: API `32757980cc71043d79c9edb09a28e93bf99c5630`
  and Supabase `d946dc2528bba33c16633e903a3b394e26d92131` (code-only head).
  API now freezes a bounded text dispatch intent, reads
  committed records in a separate scheduler transaction and reconciles
  authenticated scoped monotonic receipts. Stable job binding survives a lost
  acceptance response; fair polling cannot starve later jobs; terminal projection
  has one local revision. Forty-two native API tests passed, plus 112 pure tests
  and one historical non-native skip. Owner exact-head
  [API CI passed](https://github.com/marcelo-m7/facodi-api/actions/runs/37846789306)
  and [Supabase CI passed](https://github.com/marcelo-m7/facodi-supabase/actions/runs/37846796993).
  Those owner CI links cover preceding heads, not the successors above.
  All deployment gates passed at `94bae13`, with API `af9dd03`:
  [runtime/quick contracts](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37848130600)
  and [native integration](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37848130744).
  Successor deployment gates are required after the activity/pin follow-up.
- Supabase now accepts native `task:<uuid>` references and includes bounded
  secret-auth submit/receipt/worker endpoints. Saved metadata and analysis survive
  recovery; stale leases cannot persist or finish. At most two claims can invoke
  analysis, while later claims may finish an existing analysis checkpoint without
  another paid call. Frozen baseline/Gemini evidence contracts are used, not v3
  metadata fallback. Dependency locks and native execution are mandatory in CI.
  Thirteen Python owner tests (eight native database tests) and nineteen Deno
  tests passed. The latter use the real auth wrapper/client with native SQL.
- Terminal failure creates one native review activity for the course responsible
  user or accepted owner, without technical payload. The focused composed-registry
  replay test passed and the independent API suite passed all 42 tests.
  Two historical API-only publication fixtures fail with Learning's stricter
  rights guard; independent tests and the composed projection probe remain
  separate. No publication guard was weakened.
- The final lease guard reserves 75 seconds before a new paid call and bounds
  RPCs to 10 seconds. All 19 Deno tests/typecheck passed and
  [exact code-head CI passed](https://github.com/marcelo-m7/facodi-supabase/actions/runs/37848842873).
- The deployment candidate adds a main-only five-minute Actions wake, disabled
  unless repository variable `FACODI_CANONICAL_WORKER_ENABLED=true`. The Edge
  worker has its own default-off gate. Existing repository secrets authenticate
  a fixed endpoint without redirects/proxies, with a 100-second deadline,
  bounded discarded response and no credential in argv. GitHub schedules are
  best-effort, not a latency SLA; lost/delayed wakes recover at the next tick.
  Supabase alone owns claims/checkpoints. Disable new intake on rollback, but
  keep wake and reconciliation enabled until accepted jobs drain.
  The local pg_cron/pg_net proposal was withdrawn: managed queue grants could
  expose secret headers and the normal database role cannot revoke them.
  Probe transactions rolled back; no extension/grant persisted or remote write
  occurred. Three focused no-network wake tests passed.
- The existing deployment harness now includes a disposable native Learning
  projection probe: one canonical task, one unpublished result and attempt,
  terminal replay and preservation of human task fields. The focused real
  registry probe passed; all fixture changes roll back.
- This is an explicit-text cohort limited to 12000 UTF-8 bytes, not all-source
  parity. Scheduler activation, binary documents, transcript acquisition,
  oversized catalogs and versioned retry/cancel/input remain unfinished. Final
  exact-pin runtime/browser/restore and productive canary remain mandatory.
  No remote schema/functions, intake gate or publication were changed.

Previous intake/protocol evidence, not acceptance of the continuation heads:

- API `19.0.3.4.0` candidate: frozen execution plane, explicit managed workspace
  per Website, one canonical task, native permission checks and no legacy claim.
- Six additional native tests cover route replay, passive legacy preservation,
  missing workspace, forged executor/commands and caller rollback. API native
  suite: 35 passed; clean API plus Project install: 59 passed; two upgrades passed.
  Existing pure API suite: 112 passed, one historical non-native skip.
- Canonical intake remains off by default. The original intake-only candidate
  did not implement dispatch/receipts or Learning projection; the continuation
  above adds these for bounded text only. Do not promote it as a completed P2.
- API draft PR27: `52cfe8a414e72103a6876d1b45cb62801d3dc46f`; both owner
  [checks passed](https://github.com/marcelo-m7/facodi-api/actions/runs/37837907971).
  The first CI attempt failed on the image's setuptools requirement; the
  isolated CI environment repair was validated locally and at the new HEAD.
- Supabase draft [PR13](https://github.com/marcelo-m7/facodi-supabase/pull/13),
  candidate `a31303bf4c861efcb35e335f749cc339ac28bf1c`: additive logged pgmq queue,
  atomic scoped replay, fenced
  leased claims, immutable checkpoints and monotonic terminal receipts. Twelve
  owner tests passed locally, including seven real database tests with twenty
  enqueue transactions, twenty claims, rollback, crash recovery and role denial.
  Native schema lint and security advisors were clean. This is a database
  protocol candidate, not a worker/transport or completed integration.
  Both owner [CI gates passed](https://github.com/marcelo-m7/facodi-supabase/actions/runs/37838915221)
  at that exact source head, including the real database suite.
- Supabase MCP read-only preflight is now verified. No remote schema/functions
  changed. The sole performance advisory is an unused legacy index (informative),
  which is preserved; no unrelated index cleanup is part of P2.
- Local native logs: `/tmp/facodi-p2-intake-native.log`,
  `/tmp/facodi-p2-clean-native.log`, `/tmp/facodi-p2-upgrade-{1,2}.log`.
  Commit/CI evidence must supplement these development logs before acceptance.

## Invariants

- Project owns human/product work; Supabase owns durable technical jobs,
  attempts/checkpoints/receipts; Learning owns academic/content facts; API owns
  authenticated boundaries/adapters; Theme presents.
- Few explicitly configured permanent workspaces; one canonical native task per
  relevant new execution. Refs, never names, are identity. No mandatory technical
  subtasks, per-run Projects, historical adoption/backfill or preliminary cleanup.
- Preserve old human fields/followers/chatter/history and accepted provider
  identity. Task19 is ordinary work tracking, not a special architecture object.
- No auto-approval/publication before P3; manual locks prevail. Freeze
  `facodi_ai_learning`, no removal/new core AI dependency. P4 owns reduction.

## Controlling Call Sites

| Owner | Current path/symbol | New-cohort change |
| --- | --- | --- |
| API | `facodi_api/models/pipeline_run.py`: `submit`, `_ensure_project_task` | P1 helper in selected workspace, no per-run Project or technical subtasks |
| API | same file: `_sync_to_project_task` | Business correlation only, never overwrite human name/description |
| Learning | `facodi_learning/models/pipeline_adapter.py`: `_enqueue_pipeline_run`, `_reconcile_pipeline_receipt` | Shared authorized ORM boundary and stable task/job receipts |
| Learning | `models/analysis_job.py`, `models/slide_slide.py` | New intake cohort only; preserve domain evidence, old routes and native publication controls |
| Supabase | owning `marcelo-m7/facodi-supabase` schema/Edge sources | Durable jobs/checkpoints and authenticated idempotent callbacks |

Re-verify symbols at starting pins. Load applicable Supabase skills and inspect
the exact target/schema/functions/logs before implementation. Do not infer auth
from `verify_jwt` metadata or add ad hoc RPC clients. No production fallback.

## Delivery Sequence

1. **Inventory/cohort.** Capture passive history and accepted/in-flight provider
   consumers. Add an initially disabled new-execution routing setting and
   explicitly selected managed workspace ID/ref per company/Website. Validate
   native permissions; never find it by name or auto-create a fallback Project.
   Reuse an existing permanent Project only when conceptually suitable.
2. **Atomic intake.** Call `facodi_ensure_task` with stable intake key and persist
   a minimal dispatch intent in the existing API acceptance record, in the same
   caller transaction with full Odoo retry. Freeze route/cohort/company/actor/task
   identity. This record is compatibility/boundary evidence, not another engine.
3. **Durable dispatch.** A recoverable boundary dispatcher reads committed
   intents and submits Supabase work keyed by task ref. Never send before commit
   or depend on an in-memory after-commit callback for durability. Remote replay
   returns the same job UUID; bind it once with `facodi_bind_receipt`. Reconcile
   a crash after remote acceptance using the same key. Persist only dispatch
   intent/receipt cursor locally; technical steps stay in Supabase.
4. **Authenticated reconciliation.** Bound signed callbacks validate sender,
   task/job/company/cohort and monotonic receipt revision. Duplicate/stale events
   are no-ops or explicit conflicts, never replacement. Record canonical domain
   evidence atomically and leave content unpublished. Deduplicate human-actionable
   native activities; no checkpoint-per-chatter or second technical workflow.
5. **Consumer cutover.** Patch the inventoried API/Learning new-cohort branches
   together. Declare Project dependency in consumers, not the foundation.
   Accepted old runs retain original executor/receipt route until terminal;
   no provider mutation, adoption or mirror expansion. Theme remains presentation.
6. **Acceptance.** Test disabled routing, then a bounded disposable/private
   cohort with selected workspace and unpublished native content. Require all
   gates below. Prepare backward-compatible Supabase migrations, owner PRs and
   exact deployment pins in dependency order. Production activation is separate.
7. **Drain/rollback.** Disable new intake expansion but retain accepted new-cohort
   reconciliation until terminal. Never replay those jobs through legacy, delete
   tasks/jobs or replace provider identity. Binary rollback requires schema
   compatibility; paired DB/filestore restore follows the approved runbook.
   Historical preservation and P4/P6 retirement remain independent.

## Required Proof

- Real concurrent intake/receipts, PostgreSQL uniqueness/full transaction retry,
  same-workspace and archived task replay, one canonical task/stable job per key.
- Crashes before commit, after commit before dispatch, after remote acceptance
  before binding and around terminal reconciliation. No network exactly-once claim.
- Wrong signature/job/task/company, duplicate/out-of-order/stale revision,
  oversized callback and expired replay window fail closed without side effects.
- Retry/cancel/partial output/provider failure cannot replace identity, overwrite
  human fields, duplicate evidence or publish. Manual locks remain authoritative.
- Private/cross-company/native operator permissions and Portal/Public technical
  field denial; native share-token and Website/course visibility checks.
- Old providers/in-flight runs work unchanged; exact pre-cutover history survives
  install/two upgrades with no old refs. Native eLearning/submission/portal parity.
- Exact component CI/pins, browser desktop/mobile and paired restore; no AI removal.

Run against clean reviewed sources in the deployment owner:

```bash
bash scripts/validate-repository.sh
FACODI_API_SOURCE="$PWD/addons/facodi-api/facodi_api" \
  bash tests/test_api_e2e_isolated.sh --check-project-source
FACODI_API_SOURCE="$PWD/addons/facodi-api/facodi_api" \
  FACODI_LEARNING_FULL_TESTS=1 bash tests/test_api_e2e_isolated.sh
FACODI_REQUIRE_EMPTY_DATABASE=1 FACODI_BROWSER_ACCEPTANCE=1 \
  FACODI_BROWSER_CHROME_BIN="/path/to/approved/chromium" \
  FACODI_BROWSER_SCREENSHOT_DIR="/tmp/facodi-p2-browser" \
  FACODI_D2_BROWSER_SCREENSHOT_DIR="/tmp/facodi-p2-d2-browser" \
  bash tests/test_coolify_runtime.sh
```

Add crash/callback/cohort checks to existing owner/harness surfaces, not waived
alternative gates. Keep complete private snapshots ignored; commit sanitized
counts, exact SHAs, CI URLs and residual blockers.

## Promotion Stops

Duplicate jobs/tasks, unauthorized effects, history mutation, missing durable
intent, unbounded callback, stale overwrite, manual-lock bypass or failed
CI/runtime/restore block promotion. At the separate promotion preflight, use the
approved FACODI connector and re-read target, gates/crons, matched restore point
and actual Coolify image digest. Source version is not image identity. Preserve
the resource/volumes and migration gate. Supabase target/auth/schema approval
precedes its remote writes.