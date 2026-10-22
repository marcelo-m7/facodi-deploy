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
