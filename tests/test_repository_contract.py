from pathlib import Path
import configparser
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryContractTest(unittest.TestCase):
    def test_submodules_and_modules(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".gitmodules")
        paths = {parser[s]["path"] for s in parser.sections()}
        self.assertEqual(paths, {"addons/facodi-learning", "addons/facodi-theme"})
        self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-theme/website_facodi/__manifest__.py").is_file())

    def test_generated_credentials_and_state_are_ignored(self):
        ignored = (ROOT / ".gitignore").read_text()
        for pattern in ("gha-creds-*.json", "*.tfstate", "*.tfstate.*", ".terraform/"):
            self.assertIn(pattern, ignored)

    def test_bootstrap_declares_migratable_gcs_backend(self):
        versions = (ROOT / "infrastructure/terraform/bootstrap/versions.tf").read_text()
        self.assertIn('backend "gcs" {}', versions)
        self.assertIn("marcelo-497411-facodi-tfstate", (ROOT / "infrastructure/terraform/bootstrap/variables.tf").read_text())

    def test_terraform_never_manages_secret_payloads(self):
        forbidden = ("secret_data", "google_secret_manager_secret_version")
        for path in (ROOT / "infrastructure/terraform").rglob("*.tf"):
            text = path.read_text()
            for token in forbidden:
                self.assertNotIn(token, text, f"{token} must not appear in {path}")

    def test_production_starts_disabled_and_manual(self):
        tfvars = (ROOT / "infrastructure/terraform/environments/production/terraform.tfvars").read_text()
        self.assertIn("runtime_enabled       = false", tfvars)
        self.assertIn("public_access_enabled = false", tfvars)

        workflow = (ROOT / ".github/workflows/deploy-production.yml").read_text()
        self.assertIn("workflow_dispatch:", workflow)
        self.assertNotIn("\n  push:\n", workflow)
        self.assertIn("DEPLOY_PRODUCTION_ENABLED == 'true'", workflow)
        self.assertIn("environment: production", workflow)


if __name__ == "__main__":
    unittest.main()
