# FACODI Deploy Architecture

## Ownership

`facodi-deploy` is the integration and deployment repository for the FACODI Odoo 19 Community instance at `facodi.com`. It owns the Docker image, Coolify Compose lifecycle, migration gate, source pins, and integration tests.

Business and presentation changes remain in their owning addon repositories:

| Owner | Responsibility | Verified gitlink |
| --- | --- | --- |
| `marcelo-m7/facodi-ai` | AI runtime and Website integration | `e3e79b77588586341ba97a70f07d6d8625dd25e1` |
| `marcelo-m7/facodi-learning` | Curriculum and learning domain | `b4b9b40b1a5aa061e3f633ad5691f1409c997114` |
| `marcelo-m7/facodi-theme` | FACODI Website presentation | `c67a5e648fd581de51f2377a2b938c71a0a9147a` |

| `odoo/design-themes` | `theme_common` dependency | `a1818df4ade65406c0cacae8b1ea676e6f70095f` |

The gitlinks are the authoritative pins. The values above are verified from the superproject for this release.

## Runtime

```text
Coolify
  +-- db: PostgreSQL 16 -> postgres-data
  +-- migrate: one-shot gate -> odoo-data
  +-- odoo: Odoo 19 Community -> odoo-data -> facodi.com
```

`deploy/coolify/docker-compose.yml` is the production runtime definition. `odoo` waits for a healthy database and a successful `migrate` completion. The migration must fail closed and preserve the guarded legacy `website_facodi` to `theme_facodi` transition.

The runtime requests these modules through `FACODI_MODULES`:

- `facodi_learning`
- `theme_facodi`
- `facodi_ai`
- `facodi_ai_website`

The image also makes the pinned addon sources available. Retired Monodoo/Monynha modules are explicitly uninstalled by the migration and are not part of the installation contract.

### Supabase processing plane

Network enrichment and learning-resource analysis are owned outside the Odoo image by `marcelo-m7/facodi-supabase`. The production boundary is:

```text
Odoo submission / canonical source
  -> facodi.learning.analysis.job
  -> authenticated Supabase Edge Function
  -> metadata + AI analysis
  -> normalized immutable Odoo analysis result
  -> human review
```

Odoo authenticates server-to-server with `SUPABASE_SECRET_KEY`; `SUPABASE_URL` and the secret key must be configured together. Migration sets `facodi_learning.analysis_provider=supabase_edge` only when that pair is valid. `SUPABASE_PUBLISHABLE_KEY` and `SUPABASE_JWKS_URL` are forwarded for future lower-privilege surfaces but do not authorize the privileged analysis bridge.

Supabase does not publish courses/content, apply tags, approve mappings, or create academic equivalence. The standard Odoo records and explicit Manager review remain canonical.

On Edge failures, cross-system correlation is deliberately narrow: the private Supabase job must first persist its failed state and private diagnostics. Only then may the Edge response expose the opaque `processing_job_id` UUID. Odoo bounds the error response, accepts only that UUID, revalidates it as a trusted `SupabaseAnalysisError`, and persists only the sanitized correlation marker in job/attempt audit evidence.

## Current Live Inventory

This is a mix of authorized production observations and checked-in runtime acceptance facts. It is not a seed or an authorization to rewrite live editorial data.

| Surface | Observed state |
| --- | --- |
| Website | ID 1, `Faculdade Comunitária Digital`, domain `https://facodi.com` |
| Languages | `en_US` default; `pt_PT`, `es_ES`, `fr_FR` available |
| Website menus | `Explore`, `Community`, `About`; labels translated in all four languages |
| Menu destinations | Canonical destinations include `/slides`, `/website/search`, `/contactus`, `/blog`, `/forum`, `/sobre`, `/roadmaps`, and `/contribuir/recurso`; legacy editorial menu targets are reconciled to canonical URLs during theme upgrade |
| Public route check | Canonical `/slides`, `/blog`, `/forum`, `/contactus`, `/sobre`, `/roadmaps`, and `/contribuir/recurso` are public; legacy `/roadmap` is a permanent `301` to `/sobre#how-it-works` |
| Learning catalog | 19 active, public, published `slide.channel` training courses; 790 `slide.slide` records |
| Catalog duplicate check | No duplicate course names or `website_url` values |
| Curriculum reference | Validated, Website-published UAlg LESTI 2026/27 reference, programme code `1941`, with 43 source units |
| Public Roadmaps | `/roadmaps`, `/pt/roadmaps` and Roadmap UC detail routes are acceptance-tested public surfaces; legacy `/curriculos` and `/mapa-curricular` URLs permanently redirect |
| Legacy editorial redirects | Native Odoo `301` rewrites canonicalize `/facodi`, `/manifesto`, `/comunidade`, `/parceiros`, `/roadmap`, `/como-contribuir`, and `/contribuir`; `/roadmaps` and `/contribuir/recurso` remain canonical |
| Footer | FACODI/Odoo footer presentation remains fixed to `#0B1325` |
| Probability and Statistics | UC `19411018` has five published reusable modules, 53 existing course-content items and three approved coverage relations; these are reviewed mappings, not newly authored learning content or academic equivalence |
| Blog | `website_blog` installed; `/blog` is the standard controller route |

`slide.channel` is the only course model and `slide.slide` is canonical course content. Do not create or revise curriculum records, coverage, ECTS claims or equivalence claims without official source evidence and a Manager decision.

Curriculum audit models remain private. Public projection may elevate only enough to discover reviewed editorial records, then must query course and content records as the requesting user so Odoo publication, website and visibility rules remain authoritative.

Public and editorial learning structure is called a **Roadmap**: Roadmap → curricular unit → reusable learning module → existing course or content. `curriculum` remains the technical model namespace and the term for versioned external academic evidence, source provenance and reviewed coverage; it is not a competing public product domain.

Resource contribution is Odoo-owned by `facodi_learning`: contextual CTAs use `/contribuir/recurso` and carry `curriculum_unit_id` when a curricular-unit context exists. Valid YouTube submissions are projected to `/explorar/videos` immediately, including pending review, through a strict public view that excludes rejected submissions, contributor identity, tracking tokens, submission context and audit records. This community listing is separate from canonical `slide.slide` publication and does not bypass editorial governance. General collaboration continues through `/contactus`. `theme_facodi` may present these routes but does not own the submission model or controller.

## Historical Notes

Historical audit material is retained under `audit/`. It describes observations and remediations at the audit date, and may contain superseded deployment status. The live inventory above and the current gitlinks are the source for present-state claims; migration behavior is defined by the checked-in runtime files and tests.

## Validation Boundary

Run `git submodule update --init --recursive` before validation. The repository contract checks source paths, manifests, and that each checked-out submodule exactly matches the superproject gitlink. Runtime changes additionally require Compose configuration validation and the disposable Coolify acceptance test documented in [README.md](README.md).