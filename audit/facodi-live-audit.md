# FACODI Live Audit

Audit date: 2026-09-07
Target: https://facodi.com
Mode: read-only production audit
Production writes during this audit: 0

## Executive Summary

FACODI is serving the public Website and eLearning catalogue. The bounded public crawl returned HTTP 200 for all 94 collected same-origin URLs. The live Odoo registry contains the advanced FACODI models, their fields and ACLs; their empty tables represent unused capability, not a failed module installation. The eLearning publication state is internally consistent: 19 published courses, 790 published slides, 641 YouTube videos, and no draft content inside a published course.

The confirmed issues are:

- `SEC-001`: production credentials were exposed in the local audit context and must be rotated urgently.
- `UX-001`: the cookie banner obscures important first-viewport content at mobile width.
- `SEO-001`: the rendered Portuguese homepage and catalogue have no meta description or Open Graph description.
- `SEO-002`: localized homepage canonical URLs point to `/facodi` instead of the public localized root route.
- `AI-001`: the Website Translation profile has providers available but no active connection, so the service cannot execute an authenticated translation.
- `CONTENT-001`: two courses contain duplicate lesson titles within the same course.

No production correction was applied because the only clearly urgent operational action is secret rotation, and the remaining changes require code, editorial or administrator decisions.

## Scope And Evidence

The audit combined:

- repository and nested-repository inspection;
- saved XML-RPC baseline and schema-aware model inspection;
- installed module, Website, page, menu and language reconciliation;
- bounded GET-only crawl of public same-origin routes;
- browser screenshots and accessibility-tree inspection at desktop and mobile sizes;
- rendered DOM metadata inspection;
- eLearning publication, YouTube ID, duplicate-title and quiz-schema checks;
- ACL, record-rule, user, group, cron and external-ID snapshots;
- unauthenticated negative calls against the custom AI translation route and private FACODI models.

Saved evidence used during the audit:

- `/tmp/facodi-live-baseline.json`
- `/tmp/facodi-http-audit.json`
- `/tmp/facodi-elearning-audit.json`
- `/tmp/facodi-security-audit.json`
- `/tmp/facodi-home-desktop.png`
- `/tmp/facodi-home-mobile.png`
- `/tmp/facodi-course.txt`

Secrets, API keys, passwords and secret-bearing payloads are not reproduced here.

## Findings

### SEC-001 - Critical - Credential exposure

The untracked `.env` file contains production credential variables. During the audit, real secret values were previously read into local tool output. The values are intentionally absent from this repository. This is a confirmed local-context exposure, not a claim that `.env` is committed.

Action: rotate the Odoo API key and password and any AI key present in the exposed context, invalidate old sessions, and review retention/access to the audit transcript and tool output.

### UX-001 - Medium - Mobile cookie overlay

A 390x844 screenshot of `/pt/` shows the fixed consent banner covering the lower part of the learning-map hero. The banner is large enough to hide meaningful content before the visitor makes a choice.

Action: implement a compact mobile consent presentation with bounded height, safe-area spacing and verified keyboard focus. Test 320, 390 and 430 CSS pixel widths.

### SEO-001 - Medium - Missing descriptions

Rendered DOM inspection found no `meta[name=description]` on `/pt/` or `/pt/slides`. Both pages have `og:title` but no `og:description`.

Action: add localized authored descriptions for the homepage and catalogue and verify the rendered Open Graph values.

### SEO-002 - Medium - Homepage canonical mismatch

`/pt/` renders canonical `https://facodi.com/pt/facodi`; the English homepage similarly renders `/facodi`. The public route is the localized root, while the Website page record uses the root route.

Action: decide whether the public localized root or the internal page route is canonical, then align canonical, redirects and hreflang consistently across all four languages.

### AI-001 - High - No usable Website Translation connection

The live Website Translation profile is active, with no explicit provider and no connection. The global fallback provider is `gemini`, and both provider definitions are active, but there are zero `facodi.ai.connection` records. The service implementation requires an active resolved connection before it will call a provider. The public controller correctly rejects unauthenticated requests.

Action: configure an environment-backed provider connection through the administrator UI, then run one controlled authenticated translation test. Keep credentials out of records, logs and audit artifacts.

### CONTENT-001 - Low - Duplicate lesson titles

Two within-course duplicate pairs were confirmed:

- Course 9: slide IDs 352 and 353, `Automatic Coolify Backups to Hetzner Object Storage - 2025`.
- Course 12: slide IDs 446 and 447, `Certifications | Odoo Human Resources`.

Repeated titles such as `Guia de estudo` across different courses are expected template reuse and were not classified as findings.

Action: confirm whether each duplicate pair is intentional; otherwise rename or remove one record through normal eLearning workflows.

## Clean Checks

- Deployment module versions match the expected repository revisions for the audited modules.
- `facodi_learning`, `facodi_ai`, `facodi_ai_website`, `theme_facodi` and the canonical Monodoo modules are installed.
- All advanced FACODI learning and AI models queried in the baseline exist in the live registry with fields and ACLs.
- All 94 bounded public crawl requests returned HTTP 200.
- `robots.txt` is reachable and references `https://facodi.com/sitemap.xml`.
- `sitemap.xml` is reachable as XML.
- 19 courses are published and 790 slides are published.
- 641 published YouTube slides passed the current ID-shape check.
- No published slide was found inside a draft course.
- No published course without owned slide content was found.
- No prerequisite cycle was found in the collected course relationships.
- Unauthenticated requests to the custom translation endpoint and private FACODI dataset models were rejected by Odoo authentication/session handling.
- The single internal user observed in the snapshot is not evidence that the full role matrix has been exercised; role-specific authenticated testing remains a follow-up.

## Runtime Notes

The live Website configuration contains FACODI and a second `Monynha Softwares` Website without a domain. Both expose the FACODI theme in the collected state. This is recorded as a configuration observation, not a confirmed defect, because the intended multi-website boundary was not established by the repository contract.

The discovery setting was observed enabled in the live configuration with a batch size of 20. The discovery cron exists and is active. The analysis-job cron exists and had a recent `lastcall`; one sampled `nextcall` was already due at collection time, which is not enough by itself to prove a stuck job. Review scheduler logs and the next execution before changing cron state.

The advanced analysis, mapping, curriculum, discovery and AI request tables are empty. This is consistent with no operational workload having been run; it is not evidence that the models are missing.

## Recommended Order Of Work

1. Rotate exposed production credentials and review local audit-output retention.
2. Configure and test the Website Translation connection, or explicitly disable the feature until configured.
3. Fix mobile consent layout and verify at the target widths.
4. Correct homepage/catalogue metadata and canonical/hreflang policy.
5. Resolve the two within-course duplicate titles.
6. Repeat the authenticated role matrix, browser regression suite and post-change HTTP crawl.

The code-oriented work is captured in `audit/facodi-live-handoff-github.md`. Structured findings are in `audit/facodi-live-findings.json`.
