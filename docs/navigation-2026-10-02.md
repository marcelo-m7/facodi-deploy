# FACODI navigation repair — 2 October 2026

The native mobile accordion and desktop dropdown were both rendered because the
FACODI replacement of `website.submenu` omitted `not is_accordion_nav`. Restore
that outer branch guard, retain standard Bootstrap/Odoo behaviour, use real ARIA
panel IDs and contain the drawer. The close button is excluded from full-width
link styling. The generic mobile phone and Contact Us CTA are removed.

## Navigation

- Explore: Courses, Learning paths, Curricular units, Learning resources.
- Community: News (when published), Discussions, Contribute.
- About: Project & team (`/about#project`), Partnerships (`/partners`).
- Home and Contact remain direct destinations.
- Accessibility and cookies remain in the policy footer.
- Study areas and community videos remain reachable from `/explore`.

`facodi_learning` reconciles native menus and translations. `theme_facodi` owns
presentation. A repeated update must reuse the same native About parent even
when Odoo computes its URL as `#`.

## Editorial operation

The existing About page retains its original content and gains academic model,
author and infrastructure sections. The existing UAlg page becomes Partnerships
with UAlg, SEA-EU and Corvanis. Content is editor-owned and was applied separately
from the runtime upgrade through the Odoo connector.

`editorial/navigation-*.xml` and `navigation-translations.json` preserve the new
source content. `scripts/reconcile-navigation-editorial.py` is an idempotent,
explicit Odoo-shell replay for the `facodi` database at `https://facodi.com`.
It is not an automatic migration hook. Former standalone pages are unpublished,
not deleted. Native permanent redirects preserve `/about-ualg`, `/parceiros`,
`/academic-model`, `/about-marcelo` and `/infrastructure`.

## Validation

Theme source contracts and deployment repository/entrypoint contracts passed.
Learning Odoo installation/update tests passed after correcting the grouped
About URL regression. Theme Odoo installation/update tests passed. Native drawer
browser acceptance covers 320, 390 and 768 CSS pixels, disclosure targets,
44px controls, horizontal containment and closing.

The broad local learning source-test discovery also exposed a pre-existing
`TestContributionJourneyContract.test_private_status_and_manage_views_expose_journey`
failure (one marker in the baseline, test expects two), and cannot import Odoo
transaction tests without a local Odoo runtime. These are separate from the
remote Odoo CI gate and were not silently reported as passing.
