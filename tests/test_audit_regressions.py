from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "deploy/coolify/docker-compose.yml"
ENTRYPOINT = ROOT / "docker/entrypoint.sh"
MIGRATION = ROOT / "docker/migrate.py"


class AuditRegressionTest(unittest.TestCase):
    def test_odoo_admin_secret_is_separate_from_postgres_secret(self):
        text = COMPOSE.read_text()
        self.assertIn("SERVICE_PASSWORD_64_ODOO_ADMIN", text)
        self.assertNotIn("ODOO_ADMIN_PASSWD: $SERVICE_PASSWORD_64_POSTGRES", text)

    def test_facodi_theme_is_scoped_to_one_website(self):
        text = MIGRATION.read_text()
        self.assertIn("FACODI_WEBSITE_DOMAIN", text)
        self.assertIn("facodi_website", text)
        self.assertNotIn("for website in websites", text)

    def test_runtime_workers_are_configurable_and_not_hardcoded_to_zero(self):
        text = ENTRYPOINT.read_text()
        self.assertIn("ODOO_WORKERS", text)
        self.assertNotIn("--workers=0", text)

    def test_complete_monodoo_backend_meta_module_is_requested(self):
        text = COMPOSE.read_text()
        self.assertIn("monodoo_backend", text)


if __name__ == "__main__":
    unittest.main()
