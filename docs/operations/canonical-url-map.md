# FACODI canonical URLs and permanent redirects

This document is the production URL policy for FACODI after the D2 editorial consolidation.

## Principles

- Use **301 Moved Permanently** through Odoo `website.rewrite`.
- One concept has one canonical route.
- Do not keep duplicate editor-owned pages alive just to preserve an old URL.
- Before enabling a 301, remove any old `website.page` route collision by changing or unpublishing the obsolete page; Odoo evaluates 301/302 as a fallback after normal routes/pages.
- Keep Odoo's native language routing. Redirects are defined on the unprefixed canonical route unless production verification proves a language-specific exception is required.
- The FACODI footer remains `#0B1325`; URL consolidation must not touch shell branding.

## Canonical route map

| Concept | Canonical route |
| --- | --- |
| Homepage | `/` |
| About / project context | `/sobre` |
| Courses | `/slides` |
| Roadmaps | `/roadmaps` |
| Curricular Units | `/unidades-curriculares` |
| Contribution | `/contribuir` |
| Resource submission | `/contribuir/recurso` |
| News / Campus Bulletin | `/blog` |
| Contact | `/contactus` |

## Phase 1 — safe aliases

These aliases do not depend on editorial recomposition:

| Legacy | 301 target | Rationale |
| --- | --- | --- |
| `/facodi` | `/` | remove duplicate homepage URL |
| `/cursos` | `/slides` | native Odoo course catalogue is canonical |
| `/percursos` | `/roadmaps` | curriculum Roadmaps index is canonical |
| `/contacto` | `/contactus` | preserve legacy Portuguese Contact alias |
| `/roadmap` | `/roadmaps` | reserve Roadmap naming for the academic feature |

## Phase 2 — editorial consolidation

Apply only after the live destination is backed up and recomposed:

| Legacy | 301 target | Destination content |
| --- | --- | --- |
| `/como-funciona` | `/sobre#how-it-works` | About process section |
| `/manifesto` | `/sobre` | principles/manifesto consolidated in About |
| `/parceiros` | `/sobre` | partners/network context consolidated in About |
| `/comunidade` | `/contribuir` | community participation consolidated in Contribution |

## Live execution order

1. Read and preserve the current `website.page` / `ir.ui.view` records for the legacy and canonical routes.
2. Verify each canonical destination returns a healthy page.
3. Recompose `/sobre` and `/contribuir` with D2 components while preserving factual/editor-authored content.
4. Move or unpublish obsolete duplicate pages so they no longer own the legacy route.
5. Upsert `website.rewrite` rows with `redirect_type = '301'`, website-scoped to FACODI.
6. Verify the legacy route returns HTTP 301 and the Location target is canonical.
7. Verify the final destination returns HTTP 200 and its canonical link points to itself.
8. Re-check PT/ES/FR language routing, menu/footer links, Blog and Contact.

The redirect source of truth is `config/canonical_redirects.json`.
