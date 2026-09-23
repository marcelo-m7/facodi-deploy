# FACODI Deploy Architecture

## Ownership

`facodi-deploy` is the integration and deployment repository for the FACODI Odoo 19 Community instance at `facodi.com`. It owns the Docker image, Coolify Compose lifecycle, migration gate, source pins, and integration tests.

Business and presentation changes remain in their owning addon repositories:

| Owner | Responsibility | Verified gitlink |
| --- | --- | --- |
| `marcelo-m7/facodi-ai` | AI runtime and Website integration | `a041a674175a221c0ad6a1a97095d22e38f69e72` |
| `marcelo-m7/facodi-learning` | Curriculum and learning domain | `dc3c6334239d87f3f5f40c3203a768aeadb585db` |
| `marcelo-m7/facodi-theme` | FACODI Website presentation | `827371a1499dbe8ed1d4bed1da906aab1be7daea` |
| `marcelo-m7/monodoo` | Generic Odoo backend capabilities | `bbc6f6affc730de7cf75c98c0d6d30da10740095` |
| `marcelo-m7/monynha-odoo` | Optional Monynha modules, not automatically installed | `5c9d4513487eb87f8fd3fe36b76765f25a13096d` |
| `odoo/design-themes` | `theme_common` dependency | `a1818df4ade65406c0cacae8b1ea676e6f70095f` |

The gitlinks are the authoritative pins. The values above were verified from the superproject on 2026-09-20.

The Processing Plane source is pinned at `supabase/facodi-processing-plane`. It is intentionally not under `addons/`, is not part of the Odoo runtime image build, and is the home for FACODI Supabase migrations, Edge Functions, shared helpers and live-function snapshots.

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
- `monodoo_backend`

The image also makes the pinned addon sources available. Availability is not an installation contract: the Monynha modules are intentionally excluded from the automatic FACODI installation set.

The `supabase/facodi-processing-plane` tree is outside that runtime surface. It exists to preserve and evolve the Supabase Processing Plane without changing which sources are copied into `/mnt/extra-addons`.

## Current Live Inventory

This is an authorized read-only production observation recorded on 2026-09-16, not a seed, migration, or publication contract.

| Surface | Observed state |
| --- | --- |
| Website | ID 1, `Faculdade Comunitária Digital`, domain `https://facodi.com` |
| Languages | `en_US` default; `pt_PT`, `es_ES`, `fr_FR` available |
| Website menus | `Explore`, `Community`, `About`; labels translated in all four languages |
| Menu destinations | `/slides`, `/website/search`, `/contactus`, `/blog`, `/forum`, `/sobre`, `/roadmap` |
| Public route check | `/slides`, `/blog`, `/forum`, `/contactus`, `/sobre`, and `/roadmap` returned HTTP 200 |
| Learning catalog | 19 active, public, published `slide.channel` training courses; 790 `slide.slide` records |
| Catalog duplicate check | No duplicate course names or `website_url` values |
| Curriculum data | 0 `curriculum.reference`, 0 `curriculum.unit`, 0 `curriculum.coverage`, 0 `course.mapping`, 0 `course.candidate` |
| Blog | `website_blog` installed; `/blog` is the standard controller route |

`slide.channel` is the only course model and `slide.slide` is canonical course content. The empty curriculum tables show no imported curriculum workload. They do not justify creating curriculum records, UC mappings, coverage, ECTS, or equivalence claims without official source evidence and a manager decision.

## Historical Notes

Historical audit material is retained under `audit/`. It describes observations and remediations at the audit date, and may contain superseded deployment status. The live inventory above and the current gitlinks are the source for present-state claims; migration behavior is defined by the checked-in runtime files and tests.

## Validation Boundary

Run `git submodule update --init --recursive` before validation. The repository contract checks source paths, manifests, and that each checked-out submodule exactly matches the superproject gitlink. Runtime changes additionally require Compose configuration validation and the disposable Coolify acceptance test documented in [README.md](README.md).

When the Processing Plane scaffold changes, validate its local bootstrap contract as well: config present, live snapshots preserved, extracted function sources present, and no Dockerfile change that broadens the Odoo image build surface to include `supabase/`.