# FACODI Deploy Coolify Canonical Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `facodi-deploy` so the existing Coolify application serving `facodi.com` becomes the single canonical FACODI runtime, while preserving the current PostgreSQL database and Odoo filestore and aligning the deployed addon pins with the validated FACODI repositories.

**Architecture:** Keep one Docker Compose runtime at `deploy/coolify/docker-compose.yml` with persistent `db` and `odoo` services plus a one-shot `migrate` service. The same immutable Odoo 19 image contains `facodi_learning`, `theme_facodi`, and only `theme_common` from the pinned official design-themes repository. Deployment remains in the existing Coolify resource so project-scoped named volumes remain attached; migration is fail-closed and idempotent before the long-running Odoo service starts.

**Tech Stack:** Odoo 19 Community, PostgreSQL 16, Docker/Compose, Coolify, Bash, Python `unittest`, QWeb/Odoo Website APIs, Git submodules, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-05-facodi-deploy-coolify-canonical-runtime-design.md`

## Global Constraints

- Preserve the existing Coolify service names `db` and `odoo`.
- Preserve the existing named volumes `postgres-data` and `odoo-data`; do not add explicit Compose `name:` overrides during this migration.
- Keep `facodi-learning` pinned to `c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18`.
- Pin `facodi-theme` to `be35673a5649f5e6f7b01777905d0899e3daaf7b`.
- Add `odoo/design-themes` pinned to `a1818df4ade65406c0cacae8b1ea676e6f70095f`, exposing only `theme_common` to Odoo.
- Base the runtime image on `odoo:19.0`.
- Continue accepting the current Coolify secret contract based on `$SERVICE_PASSWORD_64_POSTGRES`; do not make a new mandatory secret part of this migration.
- English is the Website default; `pt_PT`, `es_ES`, and `fr_FR` must be active/published using standard Odoo language mechanisms.
- Do not add custom per-language QWeb branches, custom language routing, or JavaScript translation stores.
- Migration must not directly rewrite `website_page`, courses, contacts, or arbitrary Website Builder content.
- A migration failure must prevent the long-running Odoo service from starting.
- Cloud Run, Cloud SQL, Artifact Registry delivery workflows, and Terraform are removed as active runtime paths; historical state remains available through release `v0.1.0`.
- Exact-head CI must be green before merge.

---

### Task 1: Pin the canonical source composition

**Files:**
- Modify: `.gitmodules`
- Modify Gitlink: `addons/facodi-theme`
- Keep Gitlink: `addons/facodi-learning`
- Create Gitlink: `vendor/odoo-design-themes`
- Modify: `tests/test_repository_contract.py`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: Git submodule layout already used by the repository.
- Produces: exact reproducible source pins for the Docker build and later CI tasks.

- [ ] **Step 1: Write the failing repository-contract tests**

Replace the submodule contract with assertions for all three paths and exact SHAs:

```python
EXPECTED_SUBMODULES = {
    "addons/facodi-learning": "c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18",
    "addons/facodi-theme": "be35673a5649f5e6f7b01777905d0899e3daaf7b",
    "vendor/odoo-design-themes": "a1818df4ade65406c0cacae8b1ea676e6f70095f",
}


def test_submodules_and_modules(self):
    parser = configparser.ConfigParser()
    parser.read(ROOT / ".gitmodules")
    paths = {parser[s]["path"] for s in parser.sections()}
    self.assertEqual(paths, set(EXPECTED_SUBMODULES))
    self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
    self.assertTrue((ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").is_file())
    self.assertTrue((ROOT / "vendor/odoo-design-themes/theme_common/__manifest__.py").is_file())


def test_exact_integration_pins(self):
    import subprocess
    for path, expected in EXPECTED_SUBMODULES.items():
        actual = subprocess.check_output(
            ["git", "-C", str(ROOT / path), "rev-parse", "HEAD"], text=True
        ).strip()
        self.assertEqual(actual, expected, path)
```

- [ ] **Step 2: Run the contract and confirm RED**

Run:

```bash
python3 -m unittest tests/test_repository_contract.py -v
```

Expected: FAIL because `vendor/odoo-design-themes` is absent and `facodi-theme` is still pinned to `c080cd2de703a6f136dac8d0332c22590e47c618`.

- [ ] **Step 3: Update the Git submodules**

Use:

```bash
git submodule add https://github.com/odoo/design-themes.git vendor/odoo-design-themes
git -C addons/facodi-theme fetch origin be35673a5649f5e6f7b01777905d0899e3daaf7b
git -C addons/facodi-theme checkout be35673a5649f5e6f7b01777905d0899e3daaf7b
git -C vendor/odoo-design-themes checkout a1818df4ade65406c0cacae8b1ea676e6f70095f
test "$(git -C addons/facodi-learning rev-parse HEAD)" = "c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18"
```

- [ ] **Step 4: Strengthen the shell validator**

Add manifest and pin checks to `scripts/validate-repository.sh`:

```bash
test -f vendor/odoo-design-themes/theme_common/__manifest__.py

test "$(git -C addons/facodi-learning rev-parse HEAD)" = "c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18"
test "$(git -C addons/facodi-theme rev-parse HEAD)" = "be35673a5649f5e6f7b01777905d0899e3daaf7b"
test "$(git -C vendor/odoo-design-themes rev-parse HEAD)" = "a1818df4ade65406c0cacae8b1ea676e6f70095f"
```

- [ ] **Step 5: Run the contract and confirm GREEN**

Run:

```bash
bash scripts/validate-repository.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules addons/facodi-theme vendor/odoo-design-themes tests/test_repository_contract.py scripts/validate-repository.sh
git commit -m "chore: align FACODI deployment source pins"
```

---

### Task 2: Make the image match the validated FACODI composition

**Files:**
- Modify: `docker/Dockerfile`
- Modify: `tests/test_repository_contract.py`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: exact submodule pins from Task 1.
- Produces: image containing `/mnt/extra-addons/facodi_learning`, `/mnt/extra-addons/theme_facodi`, `/mnt/extra-addons/theme_common`, and no unrelated Odoo design themes.

- [ ] **Step 1: Add failing Docker composition contract tests**

Add:

```python
def test_dockerfile_bakes_only_required_odoo_modules(self):
    dockerfile = (ROOT / "docker/Dockerfile").read_text()
    self.assertIn("FROM odoo:19.0", dockerfile)
    self.assertIn("COPY addons/ /opt/facodi-addon-sources/", dockerfile)
    self.assertIn(
        "COPY vendor/odoo-design-themes/theme_common/ /opt/theme-common/theme_common/",
        dockerfile,
    )
    self.assertNotIn("COPY vendor/odoo-design-themes/ /", dockerfile)
```

- [ ] **Step 2: Run and confirm RED**

```bash
python3 -m unittest tests.test_repository_contract.RepositoryContractTest.test_dockerfile_bakes_only_required_odoo_modules -v
```

Expected: FAIL because `theme_common` is not copied by the current Dockerfile.

- [ ] **Step 3: Update the Dockerfile minimally**

Keep `odoo:19.0`, retain addon discovery, and add only the pinned `theme_common` source:

```dockerfile
COPY addons/ /opt/facodi-addon-sources/
COPY vendor/odoo-design-themes/theme_common/ /opt/theme-common/theme_common/
```

In the existing `RUN` block, after copying FACODI addon manifests, copy the official dependency with a collision guard:

```sh
test ! -e /mnt/extra-addons/theme_common
cp -a /opt/theme-common/theme_common /mnt/extra-addons/theme_common
```

- [ ] **Step 4: Run repository contract and build**

```bash
bash scripts/validate-repository.sh
docker build -f docker/Dockerfile -t facodi-odoo:coolify-plan .
docker run --rm --entrypoint bash facodi-odoo:coolify-plan -lc '
  test -f /mnt/extra-addons/facodi_learning/__manifest__.py &&
  test -f /mnt/extra-addons/theme_facodi/__manifest__.py &&
  test -f /mnt/extra-addons/theme_common/__manifest__.py &&
  test ! -d /mnt/extra-addons/theme_bewise
'
```

Expected: all commands succeed.

- [ ] **Step 5: Commit**

```bash
git add docker/Dockerfile tests/test_repository_contract.py scripts/validate-repository.sh
git commit -m "build: compose verified FACODI Odoo image"
```

---

### Task 3: Split persistent serving from one-shot migration

**Files:**
- Modify: `docker/entrypoint.sh`
- Create: `docker/migrate.py`
- Modify: `tests/test_entrypoint.sh`
- Create: `tests/test_migration_contract.py`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: environment variables `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `ODOO_DB`, `ODOO_ADMIN_PASSWD`, `FACODI_MODULES`.
- Produces: `facodi-entrypoint serve` for the long-running server and `facodi-entrypoint migrate` for one-shot migration/configuration.

- [ ] **Step 1: Write failing entrypoint tests for the new migration handoff**

Extend `tests/test_entrypoint.sh` so the mocked `odoo` binary records calls and assert that `migrate` does not directly contain the old `--update=${FACODI_MODULES}` branch. The expected handoff is:

```bash
PATH="$tmp:$PATH" \
DB_HOST=db DB_PORT=5432 DB_USER=odoo DB_PASSWORD=test-password \
ODOO_DB=facodi ODOO_ADMIN_PASSWD=test-admin \
ODOO_CONFIG_TEMPLATE="$tmp/odoo.conf" FACODI_MODULES=facodi_learning,theme_facodi \
bash "$root/docker/entrypoint.sh" migrate >"$tmp/migrate-output"

grep -Fq 'docker/migrate.py' "$tmp/migrate-output"
```

Mock `python3` in the test PATH to print its script path instead of executing it.

- [ ] **Step 2: Add failing migration contract tests**

Create `tests/test_migration_contract.py` with static assertions:

```python
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MigrationContractTest(unittest.TestCase):
    def test_migration_script_is_present_and_fail_closed(self):
        text = (ROOT / "docker/migrate.py").read_text()
        self.assertIn("website_facodi", text)
        self.assertIn("theme_facodi", text)
        self.assertIn("button_choose_theme", text)
        self.assertIn("pt_PT", text)
        self.assertIn("es_ES", text)
        self.assertIn("fr_FR", text)
        self.assertNotIn("website_page", text)
        self.assertNotIn("sudo().search", text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run and confirm RED**

```bash
bash tests/test_entrypoint.sh
python3 -m unittest tests/test_migration_contract.py -v
```

Expected: FAIL because `docker/migrate.py` does not exist and the entrypoint still performs module update directly.

- [ ] **Step 4: Refactor `docker/entrypoint.sh`**

Keep the current private runtime config generation and PostgreSQL environment setup. Preserve `serve` unchanged except for cleanup. Change `migrate` to execute the dedicated script with the generated config path:

```bash
migrate)
  exec python3 /usr/local/lib/facodi/migrate.py \
    --config "$odoo_config" \
    --database "$ODOO_DB" \
    --modules "$FACODI_MODULES"
  ;;
```

- [ ] **Step 5: Add the migration script to the image**

Update `docker/Dockerfile`:

```dockerfile
COPY docker/migrate.py /usr/local/lib/facodi/migrate.py
```

The initial `docker/migrate.py` implements only orchestration helpers and exits non-zero on ambiguous legacy state; full language/theme behavior is completed in Task 5.

- [ ] **Step 6: Run static tests and syntax checks**

```bash
bash tests/test_entrypoint.sh
python3 -m unittest tests/test_migration_contract.py -v
python3 -m py_compile docker/migrate.py
bash -n docker/entrypoint.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add docker/entrypoint.sh docker/migrate.py docker/Dockerfile tests/test_entrypoint.sh tests/test_migration_contract.py scripts/validate-repository.sh
git commit -m "refactor: isolate Coolify Odoo migration lifecycle"
```

---

### Task 4: Encode the `db -> migrate -> odoo` Coolify lifecycle

**Files:**
- Modify: `deploy/coolify/docker-compose.yml`
- Modify: `tests/test_repository_contract.py`
- Create: `.env.ci`

**Interfaces:**
- Consumes: `facodi-entrypoint migrate` from Task 3.
- Produces: Compose ordering where migration exit code gates persistent Odoo startup while preserving existing named volumes.

- [ ] **Step 1: Write failing Compose contract tests**

Replace obsolete Terraform-oriented repository tests with Coolify invariants:

```python
def test_coolify_compose_preserves_persistent_names_and_gates_odoo(self):
    compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
    self.assertIn("  db:\n", compose)
    self.assertIn("  migrate:\n", compose)
    self.assertIn("  odoo:\n", compose)
    self.assertIn("postgres-data:/var/lib/postgresql/data", compose)
    self.assertGreaterEqual(compose.count("odoo-data:/var/lib/odoo"), 2)
    self.assertIn("condition: service_completed_successfully", compose)
    self.assertIn('restart: "no"', compose)
    self.assertNotIn("name: facodi-postgres", compose)
    self.assertNotIn("5432:5432", compose)
    self.assertNotIn("8069:8069", compose)


def test_coolify_uses_existing_secret_contract(self):
    compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
    self.assertIn("$SERVICE_PASSWORD_64_POSTGRES", compose)
    self.assertNotIn("$SERVICE_PASSWORD_64_ODOO_ADMIN", compose)
```

- [ ] **Step 2: Run and confirm RED**

```bash
python3 -m unittest tests/test_repository_contract.py -v
```

Expected: FAIL because there is no `migrate` service or migration dependency.

- [ ] **Step 3: Update the Compose file**

Define a shared Odoo build/env contract with YAML anchors if they reduce duplication without obscuring Coolify parsing. Required effective services:

```yaml
services:
  db:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: $SERVICE_PASSWORD_64_POSTGRES
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 10

  migrate:
    build:
      context: .
      dockerfile: docker/Dockerfile
    command: ["migrate"]
    restart: "no"
    depends_on:
      db:
        condition: service_healthy
    environment:
      DB_HOST: db
      DB_PORT: "5432"
      DB_USER: odoo
      DB_PASSWORD: $SERVICE_PASSWORD_64_POSTGRES
      ODOO_DB: facodi
      ODOO_ADMIN_PASSWD: $SERVICE_PASSWORD_64_POSTGRES
      FACODI_MODULES: facodi_learning,theme_facodi
      PORT: "8069"
    volumes:
      - odoo-data:/var/lib/odoo

  odoo:
    build:
      context: .
      dockerfile: docker/Dockerfile
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      migrate:
        condition: service_completed_successfully
    environment:
      DB_HOST: db
      DB_PORT: "5432"
      DB_USER: odoo
      DB_PASSWORD: $SERVICE_PASSWORD_64_POSTGRES
      ODOO_DB: facodi
      ODOO_ADMIN_PASSWD: $SERVICE_PASSWORD_64_POSTGRES
      FACODI_MODULES: facodi_learning,theme_facodi
      PORT: "8069"
    volumes:
      - odoo-data:/var/lib/odoo
    expose:
      - "8069"
```

Keep the existing `/web/login` health check.

- [ ] **Step 4: Add CI-safe Compose variables**

Create `.env.ci`:

```dotenv
SERVICE_PASSWORD_64_POSTGRES=facodi-ci-password
```

Do not include production secrets.

- [ ] **Step 5: Validate the Compose model**

```bash
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
python3 -m unittest tests/test_repository_contract.py -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add deploy/coolify/docker-compose.yml .env.ci tests/test_repository_contract.py
git commit -m "feat: gate Coolify Odoo startup on migration"
```

---

### Task 5: Implement safe Odoo module, theme, and language migration

**Files:**
- Modify: `docker/migrate.py`
- Modify: `tests/test_migration_contract.py`
- Create: `tests/test_coolify_runtime.sh`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: database/config/module arguments supplied by `docker/entrypoint.sh`.
- Produces: an idempotently migrated database with FACODI modules updated, `theme_facodi` applied, English default, and `pt_PT`, `es_ES`, `fr_FR` active on the Website.

- [ ] **Step 1: Add failing behavior-contract tests**

Extend `tests/test_migration_contract.py` to require separate helpers and no direct page mutation:

```python
def test_migration_has_explicit_phases(self):
    text = (ROOT / "docker/migrate.py").read_text()
    for name in (
        "inspect_legacy_state",
        "run_module_operation",
        "configure_languages",
        "apply_theme",
    ):
        self.assertIn(f"def {name}", text)
    self.assertNotIn("website.page", text)
    self.assertNotIn("website_page", text)
```

- [ ] **Step 2: Run and confirm RED**

```bash
python3 -m unittest tests/test_migration_contract.py -v
```

Expected: FAIL until the phase helpers exist.

- [ ] **Step 3: Implement registry preflight and module operations**

`docker/migrate.py` must:

1. use `psql`/PostgreSQL metadata before Odoo mutation to detect whether `ir_module_module` exists;
2. initialize `base,facodi_learning,theme_facodi` with `--without-demo=all --stop-after-init` on a fresh database;
3. on an existing database, inspect `website_facodi` and `theme_facodi` module records;
4. abort if both records exist before the guarded transition is resolved, or if unexpected legacy XML IDs/dependent views make ownership ambiguous;
5. remove only the known legacy module/view metadata when it exactly matches the known migration shape;
6. run `odoo --stop-after-init --without-demo=all --update=facodi_learning,theme_facodi` after preflight.

Use subprocess calls with `check=True`; do not ignore non-zero Odoo exits.

- [ ] **Step 4: Configure Odoo languages and Website state through `odoo shell`**

After module operations, invoke `odoo shell` with the same config/database and execute a checked Python payload using standard models:

```python
language_codes = ("en_US", "pt_PT", "es_ES", "fr_FR")
Lang = env["res.lang"]
for code in language_codes:
    lang = Lang.with_context(active_test=False).search([("code", "=", code)], limit=1)
    if not lang:
        raise RuntimeError(f"Required Odoo language is unavailable: {code}")
    if not lang.active:
        lang.active = True

website = env["website"].search([], order="id", limit=1)
if not website:
    raise RuntimeError("No Website record exists after FACODI module installation")

langs = Lang.search([("code", "in", language_codes)])
website.write({"language_ids": [(6, 0, langs.ids)]})
en = Lang.search([("code", "=", "en_US")], limit=1)
website.default_lang_id = en

theme = env["ir.module.module"].search([("name", "=", "theme_facodi")], limit=1)
if not theme:
    raise RuntimeError("theme_facodi module registry record is missing")
theme.with_context(website_id=website.id).button_choose_theme()

env.cr.commit()
```

If Odoo 19 model field names differ, adjust to the actual Odoo 19 API observed in the disposable CI database rather than introducing custom fields.

- [ ] **Step 5: Add end-to-end disposable runtime test**

Create `tests/test_coolify_runtime.sh` that uses a unique Compose project and the canonical file:

```bash
#!/usr/bin/env bash
set -euo pipefail
project="facodi-ci-${GITHUB_RUN_ID:-local}-$$"
compose=(docker compose --project-name "$project" --env-file .env.ci -f deploy/coolify/docker-compose.yml)
trap '"${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true' EXIT

"${compose[@]}" build
"${compose[@]}" up -d db
"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm migrate
"${compose[@]}" up -d odoo
```

Then wait for health and query Website/language state via `odoo shell`. Assert:

```text
default language: en_US
active website languages include: en_US, pt_PT, es_ES, fr_FR
```

Fetch HTTP routes through the Odoo container/network and require successful responses for `/`, `/pt`, `/es`, `/fr`, and `/slides`.

- [ ] **Step 6: Run integration test and fix only observed Odoo 19 incompatibilities**

```bash
bash tests/test_coolify_runtime.sh
```

Expected: first migration succeeds; second migration also succeeds without duplicate/ambiguous state; Odoo becomes healthy; language and route assertions pass.

- [ ] **Step 7: Wire runtime integration into the validator only for CI**

Keep `scripts/validate-repository.sh` fast/static. Add syntax and contract execution there, but invoke `tests/test_coolify_runtime.sh` from GitHub Actions rather than every local static validation run.

- [ ] **Step 8: Commit**

```bash
git add docker/migrate.py tests/test_migration_contract.py tests/test_coolify_runtime.sh scripts/validate-repository.sh
git commit -m "feat: migrate FACODI Website through native Odoo lifecycle"
```

---

### Task 6: Remove the obsolete Google deployment architecture

**Files:**
- Delete: `.github/workflows/build-image.yml`
- Delete: `.github/workflows/deploy-staging.yml`
- Delete: `.github/workflows/deploy-production.yml`
- Delete: `.github/workflows/terraform-plan.yml`
- Delete: `.github/workflows/terraform-apply.yml`
- Delete: `infrastructure/terraform/**`
- Delete: `scripts/configure-database-user.sh`
- Delete: `scripts/deploy-runtime.sh`
- Delete: `scripts/verify-runtime.sh`
- Delete historical active Cloud Run plan/spec files that are preserved by release `v0.1.0`
- Modify: `.gitignore`
- Modify: `tests/test_repository_contract.py`

**Interfaces:**
- Consumes: release `v0.1.0` as historical rollback/reference boundary.
- Produces: one unambiguous active runtime architecture: Coolify Compose.

- [ ] **Step 1: Add failing no-obsolete-runtime contract**

Add:

```python
def test_obsolete_google_runtime_is_not_active(self):
    forbidden = [
        ROOT / "infrastructure/terraform",
        ROOT / ".github/workflows/terraform-plan.yml",
        ROOT / ".github/workflows/terraform-apply.yml",
        ROOT / ".github/workflows/deploy-staging.yml",
        ROOT / ".github/workflows/deploy-production.yml",
        ROOT / "scripts/deploy-runtime.sh",
        ROOT / "scripts/configure-database-user.sh",
        ROOT / "scripts/verify-runtime.sh",
    ]
    for path in forbidden:
        self.assertFalse(path.exists(), str(path))
```

- [ ] **Step 2: Run and confirm RED**

```bash
python3 -m unittest tests/test_repository_contract.py -v
```

Expected: FAIL while the old runtime files remain.

- [ ] **Step 3: Delete the obsolete paths**

Use Git removals so history remains available through Git and the `v0.1.0` release:

```bash
git rm -r infrastructure/terraform
git rm .github/workflows/build-image.yml \
       .github/workflows/deploy-staging.yml \
       .github/workflows/deploy-production.yml \
       .github/workflows/terraform-plan.yml \
       .github/workflows/terraform-apply.yml \
       scripts/configure-database-user.sh \
       scripts/deploy-runtime.sh \
       scripts/verify-runtime.sh
git rm docs/superpowers/plans/2026-09-05-facodi-deploy-cloud-run-terraform.md \
       docs/superpowers/specs/2026-09-05-facodi-deploy-cloud-run-terraform-design.md
```

- [ ] **Step 4: Simplify `.gitignore`**

Remove Terraform-only state patterns while retaining generated credentials/env/cache patterns still relevant to local tooling:

```text
gha-creds-*.json
.env
.env.*
!.env.example
!.env.ci
__pycache__/
```

- [ ] **Step 5: Run repository contract**

```bash
bash scripts/validate-repository.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: retire Cloud Run and Terraform deployment paths"
```

---

### Task 7: Replace CI with the actual Coolify runtime acceptance test

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `tests/test_repository_contract.py`

**Interfaces:**
- Consumes: canonical Compose runtime and tests from Tasks 1–6.
- Produces: exact-head evidence that the same deployment shape Coolify consumes builds, migrates twice, starts, and serves the required routes.

- [ ] **Step 1: Add workflow contract assertions**

Add:

```python
def test_ci_validates_the_canonical_coolify_runtime(self):
    workflow = (ROOT / ".github/workflows/ci.yml").read_text()
    self.assertIn("submodules: recursive", workflow)
    self.assertIn("deploy/coolify/docker-compose.yml", workflow)
    self.assertIn("tests/test_coolify_runtime.sh", workflow)
    self.assertNotIn("terraform", workflow.lower())
    self.assertNotIn("google-github-actions", workflow)
```

- [ ] **Step 2: Run and confirm RED**

```bash
python3 -m unittest tests/test_repository_contract.py -v
```

Expected: FAIL because CI still installs Terraform and validates Terraform roots.

- [ ] **Step 3: Replace `.github/workflows/ci.yml`**

The new workflow must:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  validate-coolify-runtime:
    runs-on: ubuntu-latest
    timeout-minutes: 35
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Validate repository contract
        run: bash scripts/validate-repository.sh

      - name: Validate Coolify Compose
        run: docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet

      - name: Exercise fresh migration, idempotent migration and Odoo HTTP
        run: bash tests/test_coolify_runtime.sh
```

Use a stable checkout major already accepted by GitHub runners; avoid adding third-party cloud actions.

- [ ] **Step 4: Run all static validation locally**

```bash
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml tests/test_repository_contract.py
git commit -m "ci: validate canonical Coolify runtime"
```

---

### Task 8: Rewrite operator documentation for `facodi.com`

**Files:**
- Modify: `README.md`
- Replace: `docs/operations.md`
- Modify: `docs/superpowers/specs/2026-09-05-facodi-deploy-coolify-canonical-runtime-design.md` status only
- Modify: `tests/test_repository_contract.py`

**Interfaces:**
- Consumes: final runtime behavior from Tasks 1–7.
- Produces: one operator runbook describing backup, Coolify deployment, migration, validation, and rollback.

- [ ] **Step 1: Add documentation contract tests**

Add:

```python
def test_docs_describe_coolify_as_the_only_runtime(self):
    readme = (ROOT / "README.md").read_text()
    operations = (ROOT / "docs/operations.md").read_text()
    for text in (readme, operations):
        self.assertIn("Coolify", text)
        self.assertIn("facodi.com", text)
        self.assertIn("postgres-data", text)
        self.assertIn("odoo-data", text)
        self.assertIn("v0.1.0", text)
    self.assertNotIn("Cloud Run", readme)
    self.assertNotIn("terraform apply", operations.lower())
```

- [ ] **Step 2: Run and confirm RED**

```bash
python3 -m unittest tests/test_repository_contract.py -v
```

Expected: FAIL because the current docs are Cloud Run/Terraform-first.

- [ ] **Step 3: Rewrite `README.md`**

Document:

- repository purpose: canonical Coolify deployment composition;
- exact pins for learning/theme/design-themes;
- canonical file `deploy/coolify/docker-compose.yml`;
- `db -> migrate -> odoo` lifecycle;
- current Coolify environment variable contract;
- persistent volume names;
- English/PT-PT/ES/FR language behavior;
- local static and disposable-runtime test commands;
- release `v0.1.0` as pre-refactor source snapshot.

- [ ] **Step 4: Replace `docs/operations.md` with the production runbook**

The first-deployment sequence must be explicit:

```text
1. In Coolify, stop automatic redeploy while backup is taken.
2. Back up PostgreSQL from the existing `postgres-data` volume/database.
3. Back up the matching `odoo-data` volume.
4. Record the current Coolify environment variables, domain and resource identifier.
5. Confirm the Coolify Compose path remains `deploy/coolify/docker-compose.yml`.
6. Merge/deploy the validated revision without deleting/recreating the Coolify resource.
7. Watch `db`, then one-shot `migrate`, then `odoo` logs.
8. Require healthy `/web/login`, `/`, `/pt`, `/es`, `/fr`, and `/slides`.
9. Confirm existing courses, Website pages, attachments and media still resolve.
10. If rollback is required after module migration, restore PostgreSQL + `odoo-data` together and deploy source release `v0.1.0`.
```

Also document routine redeploys: backup when schema/data migrations are expected, let `migrate` run idempotently, then verify health.

- [ ] **Step 5: Mark the approved design implemented**

Change only the design status line to:

```text
Status: implemented and validated on branch before merge
```

Do this only after the integration CI is green.

- [ ] **Step 6: Run static contracts**

```bash
bash scripts/validate-repository.sh
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/operations.md docs/superpowers/specs/2026-09-05-facodi-deploy-coolify-canonical-runtime-design.md tests/test_repository_contract.py
git commit -m "docs: make Coolify the FACODI deployment runbook"
```

---

### Task 9: Final verification and pull request

**Files:**
- No product-code changes expected; only corrective edits discovered by verification.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: reviewed PR with exact-head green CI, ready for deployment through the existing Coolify resource.

- [ ] **Step 1: Run the complete local verification matrix**

```bash
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
bash tests/test_coolify_runtime.sh
```

Expected: all PASS.

- [ ] **Step 2: Inspect the final diff for forbidden changes**

```bash
git diff main...HEAD -- deploy/coolify/docker-compose.yml docker/ .gitmodules tests/ .github/workflows/ README.md docs/operations.md
```

Verify manually that:

- volume names were not changed;
- no host PostgreSQL/Odoo port publishing was introduced;
- no `docker compose down -v` exists in deployment logic;
- no custom Website language implementation exists;
- Cloud Run/Terraform is absent from active deployment paths;
- the source pins match the approved exact SHAs.

- [ ] **Step 3: Push branch and open PR**

```bash
git push -u origin feat/coolify-canonical-runtime
gh pr create \
  --base main \
  --head feat/coolify-canonical-runtime \
  --title "Make Coolify the canonical FACODI runtime" \
  --body "Refactors facodi-deploy to the existing facodi.com Coolify runtime, preserves PostgreSQL/filestore volume identities, adds fail-closed one-shot Odoo migration, aligns validated addon pins, configures four Odoo Website languages, retires Cloud Run/Terraform delivery, and validates the exact Compose runtime in CI. Pre-change source is preserved as v0.1.0."
```

- [ ] **Step 4: Wait for exact-head CI and inspect failures from logs**

Do not merge on a stale successful run. The workflow associated with the PR head must complete successfully.

- [ ] **Step 5: Merge only after exact-head success**

After merge, verify the `main` push CI independently. Do not trigger or claim a live Coolify deployment until the user explicitly asks to perform/observe that deployment.
