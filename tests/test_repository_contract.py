from pathlib import Path
import configparser
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

EXPECTED_SUBMODULE_PATHS = {
    "addons/facodi-ai",
    "addons/facodi-learning",
    "addons/facodi-theme",
    "addons/monodoo",
    "addons/monynha-odoo",
    "vendor/odoo-design-themes",
}

EXPECTED_MONODOO_PIN = "ada105778f895087035730009e2ca42fdde3754c"

FACODI_MODULES = (
    "facodi_learning,theme_facodi,facodi_ai,facodi_ai_website,"
    "monodoo_core,monodoo_home,monodoo_theme,monodoo_appsbar"
)


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
        self.assertTrue((ROOT / "addons/monodoo/monodoo_core/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monodoo/monodoo_home/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monodoo/monodoo_theme/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monodoo/monodoo_appsbar/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monynha-odoo/theme_monynha/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monynha-odoo/monynha_content/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monynha-odoo/monynha_lead_generator/__manifest__.py").is_file())
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
            if path == "addons/monodoo":
                self.assertEqual(expected, EXPECTED_MONODOO_PIN)
            actual = subprocess.check_output(
                ["git", "-C", str(ROOT / path), "rev-parse", "HEAD"], text=True
            ).strip()
            self.assertEqual(actual, expected, path)

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
        self.assertIn("/opt/facodi-venv", dockerfile)

    def test_facodi_and_monodoo_are_auto_installed_and_runtime_secret_is_forwarded(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        self.assertGreaterEqual(compose.count(f"FACODI_MODULES: {FACODI_MODULES}"), 2)
        self.assertIn(f'FACODI_MODULES:={FACODI_MODULES}', entrypoint)
        self.assertGreaterEqual(compose.count("GEMINI_API_KEY: ${GEMINI_API_KEY:-}"), 2)

    def test_monynha_is_available_but_not_auto_installed_in_facodi(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        for module in ("theme_monynha", "monynha_content", "monynha_lead_generator"):
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
        self.assertIn("PGPASSWORD: $SERVICE_PASSWORD_64_POSTGRES", compose)
        self.assertIn("DB_PASSWORD: $SERVICE_PASSWORD_64_POSTGRES", compose)
        self.assertIn("DB_HOST: db", compose)

    def test_coolify_compose_preserves_persistent_names_and_gates_odoo(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertIn("postgres-data:/var/lib/postgresql/data", compose)
        self.assertIn("odoo-data:/var/lib/odoo", compose)
        self.assertIn("condition: service_completed_successfully", compose)
        self.assertNotIn("name: facodi-postgres-data", compose)
        self.assertNotIn("name: facodi-odoo-data", compose)

    def test_coolify_compose_checks_odoo_http_health(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertIn("http://127.0.0.1:8069/web/health", compose)

    def test_coolify_build_context_matches_project_directory(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertIn("context: ../..", compose)
        self.assertIn("dockerfile: docker/Dockerfile", compose)

    def test_ci_validates_the_canonical_coolify_runtime(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("scripts/validate-repository.sh", workflow)
        self.assertIn("docker compose", workflow)
        self.assertIn("tests/test_coolify_runtime.sh", workflow)

    def test_docs_describe_coolify_as_the_only_runtime(self):
        readme = (ROOT / "README.md").read_text()
        operations = (ROOT / "docs/operations.md").read_text()
        self.assertIn("canonical deployment-composition repository", readme)
        self.assertIn("existing Coolify resource", readme)
        self.assertIn("only active runtime architecture", readme)
        self.assertIn("Coolify", operations)
        self.assertNotIn("Google Cloud Run", readme)
        self.assertNotIn("Google Cloud Run", operations)

    def test_obsolete_google_runtime_is_not_active(self):
        for path in (
            ROOT / "cloudbuild.yaml",
            ROOT / "terraform",
            ROOT / "scripts/deploy-gcp.sh",
        ):
            self.assertFalse(path.exists(), path)
