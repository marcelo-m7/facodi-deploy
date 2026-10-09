# Isolated Processing Worker

Status: infrastructure direction explicitly approved by the owner on 2026-10-09;
implementation and integrated acceptance in progress. No production activation.

## Decision

Use a separate, resource-limited Coolify worker for heavy document conversion.
The existing converter permits 20 CPU seconds, whereas Supabase Edge permits
two CPU seconds per request. Keeping every parser in Edge cannot guarantee the
accepted PDF/DOCX coverage. GitHub Actions execution was considered but rejected
in favor of the worker's lower latency and separation from delivery runners.

Supabase remains the sole durable processing authority. The worker reuses its
canonical execution engine, claims and immutable checkpoints; API remains the
authorized input/projection boundary. Learning retains native editorial history,
review and publication. No processing moves back into Odoo and no second
scheduler, publication authority or per-execution Project is introduced.

## Runtime Boundary

Deployment owns the Compose service and its exact source revision. Supabase owns
the worker source and image recipe. The recipe pins Python/Deno image digests,
parser dependencies and the API-owned standalone converter revision. Odoo is
not installed in this image. Run as nonroot with a read-only root, temporary
storage only, one CPU, 512 MiB total memory, 64 PIDs, no capabilities or new
privileges, no public ports and a separate egress network. Never mount existing
Odoo/PostgreSQL volumes or supply their credentials.

Default-off startup performs no client creation or claim. Activation requires
the exact FACODI Supabase project and server-only modern secret. Use the pinned
standard SDK with exact RPC endpoint scope and redirects disabled. Child parsing
uses a cleared environment, isolated Python, bounded pipes, 256 MiB address
space, 20 CPU seconds and a 30-second hard deadline. Preserve the current source,
text, PDF-page and DOCX-expansion bounds without truncation.

## Integration Sequence

1. Validate shared execution and isolated conversion without changing intake.
2. Add private immutable source/catalog/result transport with scope, digest and
   byte-length verification. Accepted source/provider/actor/catalog/runtime must
   survive routing changes and retries; old jobs remain on their accepted path.
3. Route newly accepted heavy work explicitly. Require real queue races,
   acquisition/checkpoint/paid-call crash recovery, token fencing, cancellation,
   retry, lease-budget parity and one unpublished native editorial projection.
4. Consume exact green owner revisions in deployment and validate fresh install,
   repeated upgrade, passive history, runtime/browser and paired restore.
5. Verify productive target, capacity, applicable paired backup, actual image and
   a new private unpublished canary before bounded activation.

Disabling new intake must not abandon accepted jobs. Preserve reconciliation and
the workers needed to drain them; never replay legacy jobs into the new engine
or delete immutable source/results/history. P3 publication, P4 workflow reduction,
P5 Portal and P6 AI retirement retain their separate acceptance gates.

## Observed Foundation

API converter isolation source `f3258cc550ab04f712d475f87569a40ce39c8c39`
passed 105 pure contracts, including nine document boundary/error checks, and
[exact-head CI](https://github.com/marcelo-m7/facodi-api/actions/runs/37929327438).
The shared Edge boundary passed all preceding 37 Deno/native-SQL checks. Four
isolated CLI/SDK checks and five real converter checks passed. The worker image
started disabled without network and parsed actual PDF/DOCX in the restricted
container. These are local/source facts, not full source parity, remote Edge
acceptance or productive activation.

Supabase worker source `1bd60001702370da1dba3f74e4334551130d231e`
passed [exact-head CI](https://github.com/marcelo-m7/facodi-supabase/actions/runs/37932752806),
including the mandatory isolated-image, runtime and native database jobs.
It adds immutable Edge/isolated claim routing with legacy Edge defaults,
twenty concurrent mixed-runtime claims, checkpoint recovery and stale-token
fencing. Its 42 Deno and 26 Python checks passed; the latter include 21 native
database tests. Clean installation, schema lint and security advisors passed.
The composed deployment passed 71 local contracts and its optional-profile
configuration/actual restricted-container healthcheck. Exact deployment runtime,
browser, native integration and paired-restore gates are required at its final
published commit; predecessor runs do not establish successor acceptance.