# FACODI Project Foundation (INC-P1)

Status: reviewed source candidate; no production install or promotion.

`facodi_project` is an independent sibling addon in the API source repository.
It depends only on native `project`, not API, Learning, AI or Supabase. Its
version is `19.0.1.0.0`. Candidate owner commit is
`cefc014d158e9155b3ffbea36d1ebe942afdfe3b`, published in
[API PR26](https://github.com/marcelo-m7/facodi-api/pull/26).
[Owner native/pure CI](https://github.com/marcelo-m7/facodi-api/actions/runs/37709007523)
tracks this exact SHA. Deployment integration and promotion remain separate
gates; the previous accepted production/source pin is not this candidate.

## Greenfield Contract

Only explicitly configured permanent workspaces participate. Installing or
upgrading the addon does not adopt Projects, assign historical refs, migrate
pipelines or alter their followers, stages, assignees, chatter or history.
Task19 is normal implementation tracking, not a fixture. Existing permanent
workspaces may be reused later only when conceptually suitable; no preliminary
archive/delete operation is necessary.

Every NEW helper/code path prohibits a Project per execution and compulsory
technical subtasks. Existing legacy dispatch remains untouched until INC-P2;
it must not be expanded or adapted in INC-P1. This is the required clarification
to architecture PR271's Increment1 acceptance wording.

## Identity and Permissions

- A Project administrator explicitly configures a managed, company-scoped
  workspace. Its reference is a namespaced UUID, independent of its title.
- Managed new tasks receive their own UUID reference; existing tasks are not
  backfilled when a Project is opted in.
- `facodi_ensure_task(project_id, name, idempotency_key=False, facodi_ref=False,
  kind="execution", origin="api")` requires an authorized operator and native
  Project/Task access. It returns the authorized task ID and reference.
- Supply a stable key or task reference. Keys are unique within their workspace;
  refs are globally unique in their model, with disjoint Project/Task namespaces.
- Replay includes archived tasks, preserves human edits and never unarchives,
  creates a Project or creates technical subtasks. Conflicting identity/kind/
  origin fails. Accepted execution identity and workspace/company are immutable.
- `task.facodi_bind_receipt(external_ref)` binds the stable external job receipt.
  The same value is idempotent; replacement is denied. Attempt-specific metadata
  belongs to the technical plane, not this field.
- Copies have a new ref, no replay key and no receipt. Archive accepted executions
  instead of deleting them; parent deletion cannot cascade accepted executions.
- FACODI Operations implies native Project User, not Project Administrator.
  It does not broaden native visibility or company rules. Technical fields are
  group-restricted in the ORM and absent from the native portal field whitelists.
- No controller, cron, custom workflow state, target-reference model, provider
  call, publication action or automatic migration hook is added.

`auto` is workspace policy metadata only in INC-P1. It does not change Learning
policy defaults, activate processing, approve or publish. Runtime policy belongs
to INC-P3. Native forms, restricted task search and compact kanban kind/origin
are implemented. Native HTTP tests cover the standard Portal share-token route
and anonymous denial without exposing technical identity.

## Transactions and Release Gate

The helper uses database uniqueness and a savepoint. Only known identity-key
collisions become native `ConcurrencyError`, requesting a complete transaction
retry. Helpers never commit/rollback the caller, nor re-search a stale
`REPEATABLE READ` snapshot. Internal callers must provide the same outer
transaction retry boundary used by Odoo RPC. No network exactly-once guarantee.

Use the existing isolated harness after the owner source is reviewed/committed:

```bash
FACODI_API_SOURCE="$PWD/addons/facodi-api/facodi_api" \
  bash tests/test_api_e2e_isolated.sh --check-project-source
FACODI_API_SOURCE="$PWD/addons/facodi-api/facodi_api" \
  bash tests/test_api_e2e_isolated.sh
```

`--check-source` remains the historical API-only preflight. Full acceptance and
`--check-project-source` additionally require the tracked Project addon at the
same clean API-owner commit. Dirty/untracked Project sources fail before Docker
starts. The harness runs an independent Project database and repeated upgrades
before existing API/Learning checks. It does not exclude the concurrency test.

## Source Evidence

- Fresh standalone install and final-source native suite: 23 ORM/security/HTTP
  tests, zero failures/errors, on pinned disposable Odoo19/PostgreSQL16.
- Twenty separate-process races passed outside module loading: independent
  snapshots, PostgreSQL uniqueness, real full-transaction retry, one task/receipt,
  then concurrent archived replay preserving human edits. Each race has an
  absolute 60-second deadline; structured CI logs record exit codes, both task
  IDs, attempts, SQL count and elapsed seconds. Local maximum was 3.038 seconds;
  all exits zero/counts one. Same key in another authorized Project creates a
  different task. No ORM/SQL/helper mocks, vendor changes or concurrency exclusion.
- Native history captured before addon installation and compared after install
  and two upgrades: unchanged titles/descriptions, Projects, stages/states,
  active flags, assignees, followers, chatter IDs and write timestamps. Neither
  historical task nor workspace received a retroactive ref.
- Existing pure API suite: 112 passed, one historical skip.
- Deployment repository/migration contracts: 62 passed against the staged exact
  owner gitlink. The full integration/runtime acceptance follows below.
- Editor diagnostics: Pylance reports an unresolved `odoo.exceptions` import
  in `project_task.py` using the selected host `.venv`. Native Docker execution
  resolves that import and passed the native suite; editor environment
  alignment remains unverified. No interpreter/configuration was changed.

The earlier loader-bound fixture deadlocked during transaction reset. It was
replaced, not waived: mandatory standalone acceptance is now repeated in owner
CI and the deployment harness.

## Integration Evidence (2026-10-08)

- Full isolated harness at implementation baseline `e6d56e7`: 23 Project, 29 API
  and 425 Learning native tests, each with zero failures/errors. Mandatory
  standalone concurrency, pre-install history, two upgrades, old-addon upgrade,
  real authenticated HTTP/size limits/role separation, replay/publication and
  restart persistence passed. Publication occurred only in disposable fixtures.
- Complete repository validation: 67 contracts; production Compose validates.
- Disposable full composition: empty-database install, repeated migration,
  installed `facodi_project`, health/native backend and Website language/public
  route acceptance passed. Existing resources/production ports/volumes unchanged.
- Playwright desktop/mobile, native fullscreen video and D2 editorial/browser
  acceptance passed. Matched PostgreSQL/filestore backup, deliberate fixture
  mutation, restore and post-restore migration preserved Website/course/progress,
  curriculum review history and attachment payloads. Final runtime verdict PASS.
- Browser dependency matched CI (`playwright-core 1.55.0`); no source manifest
  or lockfile change. Native negative-path/shutdown logs are not substituted for
  the explicit zero-failure test verdicts.

Final owner `cefc014` differs only by the mandatory 20-race/time-bound evidence
enhancement. [Deployment PR272](https://github.com/marcelo-m7/facodi-deploy/pull/272)
repeats all integration/runtime/browser/restore gates with this final exact pin;
its exact-head remote CI is required, not inferred from baseline local results.
Merge order: reviewed API source, deployment candidate pin, then Codoo pointer.
Architecture PR271 is the independent greenfield clarification. Keep production
promotion separate: re-read the approved target/gates/crons, matched restore
point and actual Coolify image digest before any rollout. No merge that triggers
production is performed by this delivery. Productive install/image identity and
any controlled canary are not claimed.

Local logs use `/tmp/facodi-p1-*.log`; only sanitized summaries belong here.
Test stack/source identities are not production image identity. No production data, gates,
crons, Supabase functions or legacy pipeline code were changed.

## Next Increments

The [executable INC-P2 plan](inc-p2-plan.md) cuts over new executions to canonical
tasks and technical Supabase jobs, with committed dispatch intents and explicit
crash/callback/cohort/drain gates.
INC-P3 adds deterministic autonomous decision/publication, with manual locks
winning and human exceptions when evidence/guardrails fail. Learning already
has candidate auto-resolution with policy snapshots, but that is not automatic
publication. INC-P4 reduces duplicate Learning workflows after parity, INC-P5
expands native Project Portal, and INC-P6 retires AI Learning only after consumer
inventory and history preservation. No new core AI dependency is introduced.