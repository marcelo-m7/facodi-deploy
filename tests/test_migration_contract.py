from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "docker/migrate.py"


class MigrationContractTest(unittest.TestCase):
    def test_migration_script_is_present_and_fail_closed(self):
        self.assertTrue(MIGRATION.is_file(), "docker/migrate.py must exist")
        text = MIGRATION.read_text()
        self.assertIn("website_facodi", text)
        self.assertIn("theme_facodi", text)
        self.assertIn("button_choose_theme", text)
        self.assertIn("pt_PT", text)
        self.assertIn("es_ES", text)
        self.assertIn("fr_FR", text)
        self.assertNotIn("website_page", text)

    def test_migration_has_explicit_phases(self):
        self.assertTrue(MIGRATION.is_file(), "docker/migrate.py must exist")
        text = MIGRATION.read_text()
        for name in (
            "inspect_legacy_state",
            "run_module_operation",
            "configure_languages",
            "apply_theme",
        ):
            self.assertIn(f"def {name}", text)
        self.assertNotIn("website.page", text)
        self.assertNotIn("website_page", text)


if __name__ == "__main__":
    unittest.main()
