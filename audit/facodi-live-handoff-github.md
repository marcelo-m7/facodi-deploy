# FACODI Live Audit Handoff

Audit reference: `facodi-live-2026-09-07`

This handoff turns confirmed production evidence into reviewable GitHub work. No production data was changed during the audit.

## Urgent Operations

### SEC-001 - Rotate exposed credentials

Severity: critical

The local audit context previously contained real values from the untracked `.env` file. Do not add the file, its values or copied tool output to GitHub. Rotate the Odoo API key and password and any AI key that was present in the exposed context. Invalidate old sessions and review access/retention for the audit transcript.

Acceptance:

- old Odoo credentials fail;
- newly issued credentials authenticate successfully;
- no secret value appears in repository files, issue text, CI logs or audit artifacts;
- `.env` remains ignored and `.env.ci` contains deterministic non-production values only.

## Code And UX Issues

### UX-001 - Make cookie consent mobile-safe

Severity: medium

Evidence: 390x844 screenshot `/tmp/facodi-home-mobile.png`; the fixed cookie banner covers the learning-map hero.

Likely ownership: Odoo Website/theme presentation layer and consent component styling.

Acceptance:

- banner remains usable at 320, 390 and 430 CSS pixel widths;
- hero content and primary actions are not incoherently covered;
- focus order remains keyboard-accessible;
- essential and accept choices remain visible without horizontal overflow;
- reduced-motion behavior remains unchanged.

Regression commands:

```bash
python3 -m pytest tests/test_repository_contract.py -q
```

Then run the browser smoke suite at desktop and mobile widths and save before/after screenshots.

### SEO-001 - Add page descriptions

Severity: medium

Evidence: rendered `/pt/` and `/pt/slides` have no `meta[name=description]` and no `og:description`.

Likely ownership: Website page metadata/editorial configuration, with theme support only if Odoo does not emit the required tags.

Acceptance:

- descriptions exist for English, Portuguese, French and Spanish homepage routes;
- catalogue descriptions exist for the same languages;
- Open Graph descriptions are present and localized;
- descriptions do not duplicate the title or expose internal implementation details.

### SEO-002 - Align homepage canonical and hreflang policy

Severity: medium

Evidence: `/pt/` renders canonical `/pt/facodi`; English `/` renders `/facodi`, while the public homepage routes are root routes.

Likely ownership: Website page route/configuration and Odoo SEO metadata generation.

Acceptance:

- the chosen canonical policy is documented;
- `/`, `/pt/`, `/fr/` and `/es/` have canonical URLs consistent with that policy;
- hreflang links point to the same logical homepage in every language;
- no redirect loop or duplicate homepage route is introduced;
- sitemap URLs agree with the policy.

### AI-001 - Configure or gate Website Translation

Severity: high

Evidence: the live `website_translation` profile is active, has no provider or connection, and there are zero `facodi.ai.connection` records. The resolver can select the global `gemini` provider but the service requires an active connection before execution.

Likely ownership: administrator configuration first; code should make the unconfigured state obvious and prevent a misleading enabled experience.

Acceptance:

- either an environment-backed connection is configured and tested, or the feature is visibly disabled until one exists;
- one authorized Website editor can run a disposable translation;
- unauthenticated users still receive an authorization/session rejection;
- API keys are write-only and absent from request records, errors and logs;
- the profile/provider/connection precedence is covered by an automated test.

Suggested code tests:

```bash
python3 -m pytest addons/facodi-ai/facodi_ai/tests -q
python3 -m pytest addons/facodi-ai/facodi_ai_website/tests -q
```

## Editorial Follow-up

### CONTENT-001 - Resolve duplicate lesson titles

Severity: low

Confirmed pairs:

- Course 9, slide IDs 352 and 353: `Automatic Coolify Backups to Hetzner Object Storage - 2025`.
- Course 12, slide IDs 446 and 447: `Certifications | Odoo Human Resources`.

Acceptance:

- editorial owner confirms whether each pair is intentional;
- intentional duplicates gain disambiguating titles, or one duplicate is removed through normal Odoo workflow;
- source/provenance is preserved;
- the within-course duplicate-title check returns no unexpected records.

## Follow-up Validation

After any change:

1. Re-run the repository contract and relevant addon tests.
2. Re-run browser checks for homepage, catalogue, course, lesson, login and translated routes.
3. Re-check canonical, description, Open Graph, robots and sitemap output.
4. Re-run the 94-route bounded crawl and compare status/latency outliers.
5. Re-run eLearning publication invariants and duplicate checks.
6. Re-run unauthenticated negative tests and the authenticated role matrix.
7. Record old/new state for every API configuration change and keep credentials out of all evidence.
