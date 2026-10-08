# FACODI Deploy

`facodi-deploy` is the canonical deployment-composition repository for the FACODI Odoo 19 Community runtime serving `facodi.com` through the existing Coolify resource.

The repository does not own FACODI business logic. It pins independent addon repositories, builds one reproducible Odoo image, defines the canonical Coolify Compose lifecycle, and provides the migration and acceptance tests that must pass before a revision is deployed.

The [INC-P1 Project foundation](docs/facodi-project/README.md) is a greenfield
source candidate in this integration. New helpers use permanent workspaces and
canonical tasks; legacy pipelines remain untouched until INC-P2. Owner native
CI and real standalone concurrency passed; production promotion is separate.

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
| `marcelo-m7/facodi-api` | `facodi_api` (shared processing, default disabled), `facodi_project` (independent native identity) | `3891e749c05008344cca26ad099ead26ef344c6a` |
| `marcelo-m7/facodi-ai` | `facodi_ai`, `facodi_ai_learning` | `c9cf01739180b12a758b3f61082a38179e1e475b` |
| `marcelo-m7/facodi-learning` | `facodi_learning` | `1a4bb096dbc96f800732d50f1892dfa69f3f74ed` |
| `marcelo-m7/facodi-theme` | `theme_facodi` | `2cc983d6f5f99601983d57cc19ef7923aa60c7dc` |

The candidate composition uses `facodi_api 19.0.3.3.0`, `facodi_learning 19.0.2.2.0` and unchanged `theme_facodi 19.0.10.89.0`. It adds signed fail-closed webhooks, loaded health version and authorized private curriculum import. The [acceptance report](docs/facodi-api/acceptance-2026-10-07.md) distinguishes actual evidence from planned architecture. These pins do not identify the production image or authorize promotion before component approval. Contracts compare checkout with staged gitlinks; CI checks the submitted index.

### Historical Release Context

The consolidated release currently pairs `facodi_learning 19.0.1.146.0` with `theme_facodi 19.0.10.87.0`. The FACODI learning pin provides the public official-curriculum golden path and the public Explore discovery hub. Public contact intent is canonicalized through `/contact`, which preserves source/section/topic and learning context while delegating to the unified contextual intake. The public contribution front door is a single contextual intake; `/contribuir/recurso` remains only a compatibility alias to the same controller, while metadata discovery and tokenized status URLs stay stable. UAlg LESTI 2026/27 is reconciled idempotently from a curated official-source fixture, remains separate from canonical `slide.channel` courses, exposes curricular-unit detail pages and a covered/partial/gap matrix, and renders only Manager-reviewed coverage that still passes native Odoo learner visibility. Public discovery is exposed through `/explore`, `/explore/areas`, `/explore/content` and the community-submission queue at `/explore/videos`, while complete courses remain canonical in standard Odoo eLearning through `/courses` (which delegates to Odoo-native `/slides`). Valid YouTube submissions may appear in the community queue before editorial review, but rejected submissions, contributor identity, private tracking tokens, submission context and audit records are excluded from the public projection.

The Coolify acceptance gate follows a real curricular unit from the curriculum index through the matrix to its public unit page, and verifies the explicit gap state plus official-source provenance. Canonical public learning indexes now expose authored metadata through standard Odoo Website mechanisms, while legacy aliases remain permanent redirects. Explore filtering and pagination are executed with bounded Odoo ORM queries instead of Python-side catalogue filtering.

The current FACODI theme release repairs Website-specific hero COW drift so the Dither Veil keeps its canvas and source-image contract without overwriting editor-owned hero copy. The current FACODI theme release also canonicalizes legacy editorial URLs through native Odoo permanent `301` rewrites: `/facodi → /`, `/sobre → /about`, `/manifesto → /about`, `/comunidade → /about`, `/parceiros → /about`, `/roadmap → /about#how-it-works`, and legacy contribution URLs to `/contribuir/recurso`. The canonical curriculum route `/roadmaps` is never redirected. The footer remains locked to `#0B1325`.

Contextual community hand-offs now preserve curricular-unit, course and lesson context while delegating publishing to standard Odoo Forum at `/forum/<forum>/ask`; FACODI introduces no parallel discussion model. Minha FACODI also continues active learners directly to Odoo's native `slide.channel.partner.next_slide_id` when available, with theme-only presentation around that authoritative state.

The canonical authenticated learner home is the standard Odoo Portal route `/my/home`. Academic Map and Campus Pulse enrich that portal with reviewed curriculum-coverage context and recent ACL-visible Odoo Forum activity. Academic Map reports FACODI content coverage only; it does not claim academic completion or equivalence. FACODI extends the native portal controller/template with learner-only course and contribution context, while preserving native account/security cards and ownership rules. The learning shelf is derived from standard `slide.channel.partner` memberships and their native completion state; FACODI does not maintain a parallel progress tracker. Recent completed learning shown as Latest Wins comes from the learner's own standard `slide.slide.partner.completed` records, filtered back through currently visible Website content. The legacy `/minha-facodi` route is a permanent `301` alias to the standard portal.

The FACODI theme owns Website presentation and footer navigation. `/visual-direction` is the public Digital Highlighter Campus reference for palette, typography, component semantics and visual usage rules. The header renders Odoo's native Website language selector when more than one Website language is active; FACODI does not maintain a parallel language switcher. It must remain presentation-only: business data access belongs in the owning addon, not in theme QWeb templates.

Legacy resource processing has a separate ownership boundary: `marcelo-m7/facodi-supabase` owns Supabase schema, Edge Functions and processing orchestration and is not baked into the Odoo image. Existing jobs retain that provider contract. New jobs may use the opt-in `odoo_python` consumer, but only after an administrator explicitly selects it and configures an internal technical user with Pipeline Operator and eLearning Manager access. Odoo owns submissions, canonical eLearning records, immutable analysis evidence and human editorial decisions.

### FACODI Supabase runtime contract

The FACODI Supabase project `bhfywztfyidvrlarebmg` is the only supported Supabase processing target. Open2 is no longer a runtime dependency.

The supported server-side Edge surface is intentionally small:

- `v3_analyze_learning_resource` — idempotent metadata enrichment and conservative educational analysis, returning Odoo review payloads;
- `v3_discover_resource_metadata` — metadata-only discovery used through the Odoo server proxy;
- `v3_ingest_youtube_video` — canonical YouTube identity and metadata ingest persisted as processing evidence;
- `v2_ingest_youtube_video` — temporary compatibility alias backed by the same FACODI-native v3 ingest handler.

Historical Open2 mechanisms such as `v2_process_video_pipeline`, `v2_sync_object_to_odoo`, and `v2_push_odoo_learning_object` are not FACODI runtime functions. Consumers must not infer availability from old Open2 snapshots or documentation.

The API alias `video.ingest` resolves to `v3_ingest_youtube_video` by default. `FACODI_SUPABASE_VIDEO_INGEST_FUNCTION` remains an explicit compatibility override only. The Learning create/write hook remains disabled unless that override is deliberately configured, so introducing the v3 endpoint does not silently restore the old automatic export behavior.

### Current Processing Candidate

The candidate `facodi_api` 19.0.3.3.0 is separately gated. Learning delegates one `odoo_python` job to one immutable run through the ORM facade; native review controls publication. Legacy providers/history remain intact and `slide.channel`/`slide.slide` stay canonical. Project's technical mirror remains debt; the intended projection is human work only. Local real YouTube acquisition passed, while the historical productive IP block has not been retested by a canary. See the current [acceptance report](docs/facodi-api/acceptance-2026-10-07.md), not an inferred deployment state.

Configure server-only `FACODI_SUPABASE_WEBHOOK_SECRET` and `FACODI_STRIPE_WEBHOOK_SECRET` in Coolify before rollout, with corresponding sender signatures. They are distinct from outbound Supabase credentials, forwarded to `migrate` and `odoo`, and empty by default. Missing configuration returns 503 without an event. Do not weaken authentication to recover a sender that has not been configured. This source delivery never enables the production gate or cron.

The reviewed-submission trace is explicit in Odoo: a submission can be followed through its course candidate to the canonical source and unpublished `slide.slide`, then to the latest analysis job and immutable result. Canonical sources may be reused by multiple candidates only when provider identity, external resource identity and resolved target course all match; the submission records retain their own candidate provenance.

Failed Supabase analysis calls preserve a safe cross-system correlation boundary: Odoo reads a bounded error body, accepts only the opaque UUID returned as `details.processing_job_id`, revalidates it at the audit boundary, and stores no provider response details or secrets. The Edge Function returns that UUID only after the private Supabase failure row has been durably persisted; otherwise it fails closed without exposing a misleading correlation ID.

Contribution entry points across Roadmaps, curricular units, standard eLearning, Explore and Minha FACODI now converge on one context-aware intake shared by `/submissions/new` and the compatibility URL `/contribuir/recurso`. CTAs preserve their source section and related unit/module/course/item context, community-video entry points preselect Video, authenticated users receive safe contact prefill, and metadata discovery may fill resource title/language without overwriting user edits. `/contribuir/recurso` remains a compatibility entry point and `/contact` is the full general-contact intake; native `/contactus` remains available as the Odoo compatibility route. Course-scoped “Other contribution” opens a contextual contact intake, while Roadmap/UC provenance surfaces expose contextual correction intake; academic discussion still belongs to the Odoo Forum. Theme contribution snippets preserve CTA intent too: resource, collaboration and translation-improvement actions carry structured source/section context into the same intake. Contact intake adds a structured topic (collaboration, partnership, content/editorial, technical, accessibility or other), and contextual CTAs prefill the appropriate topic without exposing internal CTA slugs to contributors. The unified form returns contributors to their safe originating context (UC, Roadmap, reusable module, course, item or same-site source page) instead of always resetting navigation to Explore. Curriculum contribution/provenance extensions use translation-safe contextual CTA hooks, so localized PT/ES/FR QWeb rendering does not depend on English link text. Reusable learning-navigation contribution tabs and post-submission follow-up actions also preserve explicit source/section context instead of falling back to the generic compatibility alias.

`muk_web_theme` remains the FACODI backend theme. The deployment additionally consumes only the generic `monodoo_core` + `monodoo_home` capabilities to provide an Odoo-native application Home/launcher; the Monodoo theme, AppsBar and backend-polish suite remain retired. OnlyOffice is no longer a source or runtime dependency. The migration gate removes OnlyOffice and other known retired registrations through Odoo's standard module API before updating the canonical FACODI module set.

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
- keep English (`en_GB`) as the Website default;
- expose `pt_PT`, `es_ES` and `fr_FR` on the Website;
- load theme translations;
- apply `theme_facodi` through the Odoo theme API.

The migration does not rewrite arbitrary Website pages, courses, contacts or Website Builder content directly.

The FACODI theme no longer depends on `theme_common`. The deployment source tree and runtime image do not include `odoo/design-themes`; the preceding transition release upgraded `theme_facodi` first and retired any installed `theme_common` registration through Odoo's standard module API.

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

For legacy selections, that pair remains atomic: a partial pair fails the migration, a complete pair selects `supabase_edge`, and removing both values returns the persisted provider to deterministic `local_metadata`. An administrator's explicit `odoo_python` selection is preserved across repeated migrations and changes to legacy Supabase credentials. That selection fails closed unless `facodi_api` is installed; migration never enables `facodi_api.pipeline_enabled` and never rewrites accepted jobs.

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

The native Odoo Website navigation now groups the main discovery routes under the Explore submenu: Courses, Areas, Learning resources, Community videos, Roadmaps, and Curricular units.

The unified FACODI intake now includes a context-preserving type switcher for learning resources, contacts, corrections and questions. Switching type retains sanitized CTA provenance and public curriculum/course/lesson context; the theme renders the selector in the Digital Highlighter Campus visual language.


Contributor review now supports a non-terminal Changes Requested loop: editors leave a contributor-safe reply, the owner revises the same tracked contribution, and resubmission returns it to review without creating a duplicate record. Contributor-facing status and edit surfaces now show a privacy-safe context summary (type, source CTA label, section and still-public academic/learning context) while raw origin URLs, tracking tokens and internal review notes stay hidden. FAQ and community contact CTAs retain their exact source and preselect the Collaboration topic through the canonical `/contact` intake.
