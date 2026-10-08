# INC-P2: Canonical Execution Cutover

Status: executable delivery plan, not implemented or approved for production
rollout. Prerequisite: reviewed INC-P1 commits and exact-head CI. P1 owner is
API PR26, `e6d56e7f669737df65f1e3bec6e2e0af7b97b349`.

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