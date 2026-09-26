# FACODI Deploy

`facodi-deploy` is the canonical deployment-composition repository for the FACODI Odoo 19 Community runtime serving `facodi.com` through the existing Coolify resource.

The repository does not own FACODI business logic. It pins independent addon repositories, builds one reproducible Odoo image, defines the canonical Coolify Compose lifecycle, and provides the migration and acceptance tests that must pass before a revision is deployed.

## Canonical runtime

The only active runtime architecture in this repository is:

```text
Coolify
  |
  +--> db       PostgreSQL 16
  |      |
  |      +--> postgres-data
  |
  +--> migrate  one-shot, fail-closed migration gate
  |      |
  |      +--> odoo-data
  |
  +--> odoo     persistent Odoo 19 Community service
         |
         +--> odoo-data
         +--> facodi.com
```

The canonical Compose file is:

```text
deploy/coolify/docker-compose.yml
```

The `odoo` service starts only after PostgreSQL is healthy and the one-shot `migrate` service exits successfully. A failed migration therefore blocks the long-running application from starting.

The existing Coolify resource and its project-scoped named volumes must be preserved. Do not recreate the resource merely to deploy a new revision, and do not introduce explicit Compose `name:` overrides for these volumes:

- `postgres-data` — PostgreSQL data;
- `odoo-data` — Odoo filestore and persistent application data.

## Source composition

A `facodi-deploy` commit pins the exact source revisions baked into its Odoo image. The authoritative pins are the superproject gitlinks; this table documents the revisions selected by this integration:

| Source | Runtime modules | Pinned revision |
| --- | --- | --- |
| `marcelo-m7/facodi-ai` | `facodi_ai`, `facodi_ai_website` | `e3e79b77588586341ba97a70f07d6d8625dd25e1` |
| `marcelo-m7/facodi-learning` | `facodi_learning` | `b4b9b40b1a5aa061e3f633ad5691f1409c997114` |
| `marcelo-m7/facodi-theme` | `theme_facodi` | `c67a5e648fd581de51f2377a2b938c71a0a9147a` |
| `odoo/design-themes` | only `theme_common` | `a1818df4ade65406c0cacae8b1ea676e6f70095f` |

The FACODI learning pin provides the public official-curriculum golden path and the public Explore discovery hub. UAlg LESTI 2026/27 is reconciled idempotently from a curated official-source fixture, remains separate from canonical `slide.channel` courses, exposes curricular-unit detail pages and a covered/partial/gap matrix, and renders only Manager-reviewed coverage that still passes native Odoo learner visibility. Public discovery is exposed through `/explorar`, `/explorar/areas`, `/explorar/conteudos` and the community-submission queue at `/explorar/videos`, while complete courses remain canonical in standard Odoo eLearning under `/slides`. Valid YouTube submissions may appear in the community queue before editorial review, but rejected submissions, contributor identity, private tracking tokens, submission context and audit records are excluded from the public projection.

The Coolify acceptance gate follows a real curricular unit from the curriculum index through the matrix to its public unit page, and verifies the explicit gap state plus official-source provenance.

The FACODI theme owns Website presentation and footer navigation. It must remain presentation-only: business data access belongs in the owning addon, not in theme QWeb templates.

Resource processing has a separate ownership boundary: `marcelo-m7/facodi-supabase` owns Supabase schema, Edge Functions and processing orchestration. It is intentionally not baked into the Odoo image. Odoo owns submissions, canonical eLearning records, immutable analysis evidence and human editorial decisions; Supabase performs network enrichment and analysis.

The reviewed-submission trace is explicit in Odoo: a submission can be followed through its course candidate to the canonical source and unpublished `slide.slide`, then to the latest analysis job and immutable result. Canonical sources may be reused by multiple candidates only when provider identity, external resource identity and resolved target course all match; the submission records retain their own candidate provenance.

Failed Supabase analysis calls preserve a safe cross-system correlation boundary: Odoo reads a bounded error body, accepts only the opaque UUID returned as `details.processing_job_id`, revalidates it at the audit boundary, and stores no provider response details or secrets. The Edge Function returns that UUID only after the private Supabase failure row has been durably persisted; otherwise it fails closed without exposing a misleading correlation ID.

This release also connects contribution entry points across Roadmaps, curricular units, standard eLearning surfaces and homepage/community snippets to the Odoo-owned guided resource workflow at `/contribuir/recurso`. Curricular-unit CTAs preserve their unit context; `/contactus` remains the separate general-collaboration route.

Retired Monodoo and Monynha modules are not source dependencies or runtime modules. The migration gate removes known historical registrations through Odoo's standard module API before updating the canonical FACODI module set.

The repository contract validates the expected source paths, required addon manifests and the exact checked-out submodule revision against each superproject gitlink, so the deployment source composition cannot silently drift from the commit being deployed.

## Migration lifecycle

The runtime image exposes two entrypoint modes:

```text
serve    -> long-running Odoo HTTP process
migrate  -> one-shot database/module/theme/language migration
```

For a fresh database, the migration initializes Odoo and the canonical FACODI modules without demo data. For an existing database it performs a guarded preflight, initializes any newly required module that is not yet installed, and then updates the complete requested module set. The known historical `website_facodi` presentation-only transition is accepted only when its ownership shape is unambiguous; otherwise migration fails closed.

After module operations, standard Odoo mechanisms are used to:

- activate English, Portuguese (Portugal), Spanish and French;
- keep English (`en_US`) as the Website default;
- expose `pt_PT`, `es_ES` and `fr_FR` on the Website;
- load theme translations;
- apply `theme_facodi` through the Odoo theme API.

The migration does not rewrite arbitrary Website pages, courses, contacts or Website Builder content directly.

## Coolify environment contract

The canonical Compose deployment keeps the existing Coolify-generated PostgreSQL secret contract:

```text
$SERVICE_PASSWORD_64_POSTGRES
```

The core database/Odoo lifecycle still uses the existing generated Coolify secrets. The optional FACODI processing-plane integration is activated only when the following server-side pair is configured together:

```text
SUPABASE_URL
SUPABASE_SECRET_KEY
```

When that pair is present, the migration fail-closes on malformed configuration and sets `facodi_learning.analysis_provider=supabase_edge`. Removing both values explicitly returns the persisted provider to the deterministic `local_metadata` fallback, so a stale Supabase selection cannot survive without runtime credentials. The Odoo service delegates resource enrichment/analysis to the versioned Supabase Edge Function instead of performing provider-specific analysis locally.

The Compose runtime also forwards `SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_JWKS_URL` for future public-safe/authenticated processing-plane surfaces. Neither is used as the privileged Odoo-to-Supabase credential. `GEMINI_API_KEY` remains server-only and may be forwarded to the authenticated Edge call as a transitional fallback until that provider secret is configured directly in Supabase.

No Supabase or Gemini secret is committed to this repository.

## Validation

Initialize all pinned sources first:

```bash
git submodule update --init --recursive
```

Run the fast repository contract and Compose validation:

```bash
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
```

Run the disposable end-to-end runtime acceptance test:

```bash
bash tests/test_coolify_runtime.sh
```

That test builds the canonical image, creates disposable volumes, runs migration twice to prove idempotency, starts Odoo, verifies Website language state, authenticates a disposable admin session in a real Chromium browser, and checks the FACODI Website/eLearning routes. The host port used by Chromium is exposed only through `tests/docker-compose.ci.yml`; the production Coolify Compose file does not publish Odoo directly.

GitHub Actions runs the same canonical Coolify acceptance path on pull requests and on `main`.

## Architecture inventory

[`ARCHITECTURE.md`](ARCHITECTURE.md) records the ownership boundary, source pins, runtime module contract, and a dated read-only inventory of the live Website, navigation, and learning data. It separates deployment contracts from observations so operational facts do not become implicit migration behavior.

## Deployment and rollback boundary

Operational deployment must update the existing Coolify resource instead of replacing it, so `postgres-data` and `odoo-data` remain attached.

Release `v0.1.0` is the preserved source snapshot from before the Coolify-canonical refactor. It is a source/history rollback boundary, not a promise that a newer database can be downgraded without restoring persistence.

If a deployed migration must be rolled back, restore the matching PostgreSQL backup and `odoo-data` backup together, then deploy the known-good source revision. See [`docs/operations.md`](docs/operations.md) for the production procedure.

## Security and operational invariants

- no plaintext production secrets are committed;
- PostgreSQL and Odoo ports are not published directly to the host by the production Compose file;
- migration failure prevents `odoo` startup;
- deploys must not run `docker compose down -v` against the production resource;
- persistent volume names and the existing Coolify resource identity must be preserved;
- language handling remains standard Odoo Website behavior;
- exact source pins are part of the repository contract.
