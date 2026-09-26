from pathlib import Path
import configparser
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

EXPECTED_SUBMODULE_PATHS = {
    "addons/facodi-ai",
    "addons/facodi-learning",
    "addons/facodi-theme",
    "addons/muk_web_theme-19.0.1.4.9",
    "addons/onlyoffice_odoo",
    "vendor/odoo-design-themes",
}

FACODI_MODULES = "facodi_learning,theme_facodi,facodi_ai,facodi_ai_website,muk_web_theme,onlyoffice_odoo,website_forum,website_slides_forum"


class RepositoryContractTest(unittest.TestCase):
    def test_submodules_and_modules(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".gitmodules")
        paths = {parser[s]["path"] for s in parser.sections()}
        self.assertEqual(paths, EXPECTED_SUBMODULE_PATHS)
        self.assertTrue((ROOT / "addons/facodi-ai/facodi_ai/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-ai/facodi_ai_website/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-ai/requirements.txt").is_file())
        self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/muk_web_theme-19.0.1.4.9/muk_web_theme/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/onlyoffice_odoo/onlyoffice_odoo/__manifest__.py").is_file())
        self.assertTrue((ROOT / "vendor/odoo-design-themes/theme_common/__manifest__.py").is_file())

    def test_exact_integration_pins_match_superproject_gitlinks(self):
        """The superproject gitlink is the single source of truth for every pin."""
        for path in sorted(EXPECTED_SUBMODULE_PATHS):
            tree_line = subprocess.check_output(
                ["git", "-C", str(ROOT), "ls-tree", "HEAD", path], text=True
            ).strip()
            self.assertTrue(tree_line, path)
            mode_type_sha, _ = tree_line.split("\t", 1)
            mode, object_type, expected = mode_type_sha.split()
            self.assertEqual(mode, "160000", path)
            self.assertEqual(object_type, "commit", path)
            actual = subprocess.check_output(
                ["git", "-C", str(ROOT / path), "rev-parse", "HEAD"], text=True
            ).strip()
            self.assertEqual(actual, expected, path)

    def test_d1_learning_interfaces_browser_acceptance_contract(self):
        theme_manifest = (ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").read_text()
        learning_manifest = (ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").read_text()
        self.assertIn('"version": "19.0.10.1.0"', theme_manifest)
        self.assertIn('"version": "19.0.1.24.0"', learning_manifest)

        browser = ROOT / "tests/test_campus_paper_browser.mjs"
        self.assertTrue(browser.is_file(), str(browser))
        browser_source = browser.read_text()
        for marker in (
            "facodi-learning-catalogue-hero",
            "facodi-course-study-shell",
            "facodi-roadmap-study-path",
            "facodi-filter-sheet",
            "facodi-unit-layout",
            "facodi-reference-rail",
            "facodi-module-detail",
            "document.documentElement.scrollWidth",
            "window.innerWidth + 1",
        ):
            self.assertIn(marker, browser_source)

        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        self.assertIn("FACODI_BROWSER_ACCEPTANCE", runtime)
        self.assertIn("tests/test_campus_paper_browser.mjs", runtime)
        for variable in (
            "FACODI_BROWSER_COURSE_ROUTE",
            "FACODI_BROWSER_ROADMAP_ROUTE",
            "FACODI_BROWSER_UNIT_ROUTE",
            "FACODI_BROWSER_MODULE_ROUTE",
        ):
            self.assertIn(variable, runtime)

        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("actions/setup-node@v4", workflow)
        self.assertIn("playwright-core@1.55.0", workflow)
        self.assertIn("FACODI_BROWSER_ACCEPTANCE", workflow)
        self.assertIn("facodi-browser-acceptance", workflow)
        self.assertIn("actions/upload-artifact@v4", workflow)

    def test_d2_editorial_public_pages_browser_acceptance_contract(self):
        theme_manifest = (ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").read_text()
        self.assertIn('"version": "19.0.10.1.0"', theme_manifest)
        self.assertIn('"website_blog"', theme_manifest)

        fixture = ROOT / "tests/ci_seed_d2_editorial_runtime.py"
        browser = ROOT / "tests/test_d2_editorial_browser.mjs"
        runtime_gate = ROOT / "tests/test_d2_editorial_runtime.sh"
        for path in (fixture, browser, runtime_gate):
            self.assertTrue(path.is_file(), str(path))

        browser_source = browser.read_text()
        for marker in (
            "facodi-project-story",
            "facodi-principles-ledger",
            "facodi-contribution-board",
            "facodi-blog-index",
            "facodi-bulletin-card",
            "facodi-blog-article",
            "facodi-contact-page",
            "facodi-contact-form-sheet",
            "facodi-policy-document",
            "document.documentElement.scrollWidth",
            "window.innerWidth + 1",
        ):
            self.assertIn(marker, browser_source)

        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        self.assertIn('bash tests/test_d2_editorial_runtime.sh "$project"', runtime)

        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("FACODI_D2_BROWSER_SCREENSHOT_DIR", workflow)
        self.assertIn("facodi-d2-browser-acceptance", workflow)

    def test_theme_permanent_redirect_release_contract(self):
        theme_root = ROOT / "addons/facodi-theme/theme_facodi"
        manifest = (theme_root / "__manifest__.py").read_text()
        self.assertIn('"version": "19.0.10.1.0"', manifest)
        self.assertTrue((theme_root / "data/website_rewrites.xml").is_file())
        self.assertTrue(
            (
                theme_root
                / "migrations/19.0.10.1.0/post-10-permanent-editorial-redirects.py"
            ).is_file()
        )

    def test_dockerfile_bakes_only_required_odoo_modules(self):
        dockerfile = (ROOT / "docker/Dockerfile").read_text()
        self.assertIn("FROM odoo:19.0", dockerfile)
        self.assertIn("COPY addons/ /opt/facodi-addon-sources/", dockerfile)
        self.assertIn(
            "COPY vendor/odoo-design-themes/theme_common/ /opt/theme-common/theme_common/",
            dockerfile,
        )
        self.assertNotIn("COPY vendor/odoo-design-themes/ /", dockerfile)

    def test_dockerfile_installs_facodi_ai_python_runtime(self):
        dockerfile = (ROOT / "docker/Dockerfile").read_text()
        self.assertIn("python3-venv", dockerfile)
        self.assertIn("/opt/facodi-addon-sources/facodi-ai/requirements.txt", dockerfile)
        self.assertIn("pydantic_ai", dockerfile)
        self.assertIn("PyJWT", dockerfile)
        self.assertIn("/opt/facodi-venv", dockerfile)

    def test_facodi_modules_are_auto_installed_and_runtime_secret_is_forwarded(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        self.assertGreaterEqual(compose.count(f"FACODI_MODULES: {FACODI_MODULES}"), 2)
        self.assertIn(f'FACODI_MODULES:={FACODI_MODULES}', entrypoint)
        self.assertGreaterEqual(compose.count("GEMINI_API_KEY: ${GEMINI_API_KEY:-}"), 2)
        for variable in (
            "SUPABASE_URL",
            "SUPABASE_SECRET_KEY",
            "SUPABASE_PUBLISHABLE_KEY",
            "SUPABASE_JWKS_URL",
        ):
            self.assertGreaterEqual(
                compose.count(f"{variable}: ${{{variable}:-}}"),
                2,
            )

    def test_standard_forum_modules_are_explicit_runtime_capabilities(self):
        self.assertIn("website_forum", FACODI_MODULES.split(","))
        self.assertIn("website_slides_forum", FACODI_MODULES.split(","))

    def test_removed_addon_sources_are_not_present_in_runtime_contract(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        for module in ("monodoo", "monynha"):
            self.assertNotIn(module, compose)
            self.assertNotIn(module, entrypoint)

    def test_generated_local_state_is_ignored(self):
        ignored = (ROOT / ".gitignore").read_text()
        for pattern in (
            "gha-creds-*.json",
            ".env",
            ".env.*",
            "!.env.example",
            "!.env.ci",
            "__pycache__/",
        ):
            self.assertIn(pattern, ignored)
        for obsolete in ("*.tfstate", "*.tfstate.*", ".terraform/"):
            self.assertNotIn(obsolete, ignored)

    def test_coolify_compose_maps_generated_secrets(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertGreaterEqual(compose.count("$SERVICE_PASSWORD_64_POSTGRES"), 3)
        self.assertGreaterEqual(compose.count("$SERVICE_PASSWORD_64_ODOO_ADMIN"), 2)
        self.assertNotIn("${POSTGRES_PASSWORD}", compose)
        self.assertNotIn("${ODOO_ADMIN_PASSWD}", compose)

    def test_coolify_preview_uses_generated_database_service_name(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertGreaterEqual(
            compose.count("DB_HOST: ${SERVICE_NAME_DB:-db}"),
            2,
        )
        self.assertNotIn("DB_HOST: db\n", compose)

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
        self.assertNotIn("name: facodi-odoo", compose)
        self.assertNotIn("5432:5432", compose)
        self.assertNotIn("8069:8069", compose)

    def test_coolify_compose_checks_odoo_http_health(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertIn("http://127.0.0.1:$${PORT}/web/login", compose)
        self.assertIn("start_period: 60s", compose)

    def test_coolify_build_context_matches_project_directory(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        runtime_test = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        self.assertGreaterEqual(compose.count("context: ."), 2)
        self.assertNotIn("context: ../..", compose)
        self.assertIn('--project-directory "$root"', runtime_test)

    def test_obsolete_google_runtime_is_not_active(self):
        forbidden = [
            ROOT / "infrastructure/terraform",
            ROOT / ".github/workflows/build-image.yml",
            ROOT / ".github/workflows/terraform-plan.yml",
            ROOT / ".github/workflows/terraform-apply.yml",
            ROOT / ".github/workflows/deploy-staging.yml",
            ROOT / ".github/workflows/deploy-production.yml",
            ROOT / "scripts/deploy-runtime.sh",
            ROOT / "scripts/configure-database-user.sh",
            ROOT / "scripts/verify-runtime.sh",
            ROOT / "docs/superpowers/plans/2026-09-05-facodi-deploy-cloud-run-terraform.md",
            ROOT / "docs/superpowers/specs/2026-09-05-facodi-deploy-cloud-run-terraform-design.md",
        ]
        for path in forbidden:
            self.assertFalse(path.exists(), str(path))

    def test_ci_validates_the_canonical_coolify_runtime(self):
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
        self.assertIn("submodules: recursive", workflow)
        self.assertIn("deploy/coolify/docker-compose.yml", workflow)
        self.assertIn("tests/test_coolify_runtime.sh", workflow)
        self.assertNotIn("terraform", workflow.lower())
        self.assertNotIn("google-github-actions", workflow)

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

if __name__ == "__main__":
    unittest.main()
