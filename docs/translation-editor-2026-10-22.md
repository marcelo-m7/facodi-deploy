# FACODI — Odoo 19 Website translation-editor hotfix (2026-10-22)

## Symptom
Website → Edit → Translations raised RPC_ERROR on model `ir.ui.view` when `render_public_asset` compiled `theme_facodi.s_facodi_course_showcase`, because a persisted language variant called `request.lang.code`. Odoo 19 doesn't offer that attribute in the public asset-rendering context.

## Source of fix
Theme owner: https://github.com/marcelo-m7/facodi-theme/pull/142

Expected module: `theme_facodi 19.0.10.91.0`. The post-migration replaces only the deprecated QWeb expression `request.lang.code` with `env.lang` **within each language value of the saved JSONB `ir_ui_view.arch_db`**, scoped to theme templates and website-bound copies. This retains source/localized editorial HTML and is idempotent.

## Source promotion & deploy
1. Merge theme PR only after integration CI passes.
2. Pin its **exact merged commit** as a Git submodule (mode 160000) at `addons/facodi-theme` in a separate deploy PR; do not copy theme files into the superproject.
3. Pass deploy CI and merge. The canonical Compose `deploy/coolify/docker-compose.yml` has a `migrate` one-shot service and the `odoo` service depends on successful completion. Confirm the current Coolify resource still uses this Compose definition.
4. Before running any migration, confirm paired database + Odoo filestore backup and rollback readiness. Do not destroy or reset the existing database.
5. Check new `theme_facodi` installed version via ORM, and inspect the affected `ir.ui.view` for en_GB/pt_PT/es_ES/fr_FR.
6. Reproduce original action in Website Builder translation editor and check the formerly failing `render_public_asset` call. Test public /en/, /pt/, /es/, /fr/ and ensure home/course CTA copy and HTML survive.
7. Only after editor works, fill missing translations using standard Odoo translation editor or module i18n (never reapply stale archived QWeb views).

## Acceptance evidence
- Failing reference: `ir.ui.view` id 5200 (course showcase), public asset render in `en_GB`.
- Prior installed module version observed 2026-10-22: `19.0.10.90.0`.
- Static `.po` catalogs `pt.po`, `es.po`, `fr.po` have entries for the main theme terms; no simple empty `msgstr` gaps detected. This is not proof that all editor-managed page content is translated.
- Module source QWeb already uses native translatable strings. The change specifically repairs *persisted/localized* views.
- If Coolify did not redeploy or Odoo module remains 19.0.10.90.0, the fix has **not** reached production; do not report completion.
- Do not log private records, auth tokens or participant data to public CI.

## Verification update — 2026-10-25

The merged deployment `main` is `18836f6330a59f720e1c728d34881cfc9952d92f`, pinning theme `f5aa0db52891a10ac4096fe76e5875e21db28e08` and Learning `dee9b7b0054a8c6b5bfe681e9757138e02375d66`. Read-only production ORM returned `theme_facodi 19.0.10.91.0` and `facodi_learning 19.0.2.3.2` in state `installed`; views #5200 and #6762 remained active. The current-language `arch_db` reads contained no `request.lang` expression. Public desktop browser checks displayed the homepage's three highlighted courses in EN/PT/ES/FR, all three destination courses, and a news article after switching PT → ES → FR → EN.

The main deploy CI passed on commit `18836f6`. API isolated runtime initially failed during an Ubuntu package-index download (`Hash Sum mismatch`), before application tests; a second attempt on the same commit succeeded: https://github.com/marcelo-m7/facodi-deploy/actions/runs/39770021907.

**These checks do not close the release gate:**

1. Capture the exact **Coolify deployed source SHA**, Docker image digest, build/deployment ID, effective `deploy/coolify/docker-compose.yml`, `migrate` one-shot exit code/logs and Odoo health. Repository pins and ORM versions are different layers of proof.
2. Confirm paired, restorable PostgreSQL + Odoo filestore backups and identify the rollback release before any subsequent migration. Do not recreate or detach persistent volumes.
3. In an **authenticated** Odoo browser, reproduce Website → Edit → Translate on home and blog for EN/PT/ES/FR, verify no `render_public_asset` RPC error, and save desktop/mobile screenshots and the test record in task #299.
4. Complete the Learning draft/review/publish smoke workflow without unreviewed public publication. The existence of a post-upgrade unpublished draft only confirms the persisted draft state, not approval enforcement end-to-end.
5. Keep the editorial homepage view #6762 and its exact archival XML intact. Production parent view #5200 contains a `<section>` with class `s_dynamic_snippet_content`, while the currently deployed theme source uses a `<div>`; therefore the archived XPath is not portable between the two. The candidate-preparation helper `scripts/prepare_home_curated_snapshot.py` is introduced separately in [theme PR #144](https://github.com/marcelo-m7/facodi-theme/pull/144) and **is absent from the theme commit pinned here (`f5aa0db`)**. For any future **manual** recovery, first confirm that a reviewed theme revision containing that helper is available and execute the helper from that explicitly selected source checkout with an exported parent, inspect the generated candidate, and test on staging before applying anything in production. Do not assume this repository's current submodule includes the helper. The snapshot remains excluded from the module manifest.

Do not mark the rollout fully accepted until the missing operational and authenticated-browser evidence is attached. Documentation-only changes here do not require a new module migration, but a commit pushed to a Coolify-watched ref can still initiate deployment and must be handled as a production operation.
