from pathlib import Path
import configparser
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

EXPECTED_SUBMODULES = {
    "addons/facodi-ai": "f4c6bbc5cdffd5e4db8b022f43258e363bd7a25b",
    "addons/facodi-learning": "c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18",
    "addons/facodi-theme": "be35673a5649f5e6f7b01777905d0899e3daaf7b",
    "addons/monynha-odoo": "96c03e92a54ca9ca4e4f32a1307fd9bba36949ce",
    "vendor/odoo-design-themes": "a1818df4ade65406c0cacae8b1ea676e6f70095f",
}


class RepositoryContractTest(unittest.TestCase):
    def test_submodules_and_modules(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".gitmodules")
        paths = {parser[s]["path"] for s in parser.sections()}
        self.assertEqual(paths, set(EXPECTED_SUBMODULES))
        self.assertTrue((ROOT / "addons/facodi-ai/facodi_ai/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-ai/facodi_ai_website/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-ai/requirements.txt").is_file())
        self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monynha-odoo/theme_monynha/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monynha-odoo/monynha_lead_generator/__manifest__.py").is_file())
        self.assertTrue((ROOT / "vendor/odoo-design-themes/theme_common/__manifest__.py").is_file())

    def test_exact_integration_pins(self):
        for path, expected in EXPECTED_SUBMODULES.items():
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
        self.assertIn("addons/facodi-ai/requirements.txt", dockerfile)
        self.assertIn("pydantic_ai", dockerfile)
        self.assertIn("/opt/facodi-venv", dockerfile)

    def test_facodi_ai_is_auto_installed_and_runtime_secret_is_forwarded(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertGreaterEqual(
            compose.count("FACODI_MODULES: facodi_learning,theme_facodi,facodi_ai,facodi_ai_website"),
            2,
        )
        self.assertGreaterEqual(compose.count("GEMINI_API_KEY: ${GEMINI_API_KEY:-}"), 2)

    def test_monynha_is_available_but_not_auto_installed_in_facodi(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        self.assertNotIn("theme_monynha", compose)
        self.assertNotIn("monynha_lead_generator", compose)
        self.assertNotIn("theme_monynha", entrypoint)
        self.assertNotIn("monynha_lead_generator", entrypoint)

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
        self.assertNotIn("$SERVICE_PASSWORD_64_ODOO_ADMIN", compose)
        self.assertNotIn("${POSTGRES_PASSWORD}", compose)
        self.assertNotIn("${ODOO_ADMIN_PASSWD}", compose)

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
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
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
