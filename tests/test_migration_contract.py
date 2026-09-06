from pathlib import Path
import argparse
import importlib.util
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "docker/migrate.py"


def load_migration_module():
    spec = importlib.util.spec_from_file_location("facodi_migrate", MIGRATION)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


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

    def test_existing_database_initializes_required_modules_before_update(self):
        """A newly introduced addon must be installed on an already-existing DB."""
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules="monodoo_core,monodoo_home",
        )
        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(migration, "psql_scalar", return_value=""),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
        ):
            migration.main()

        self.assertEqual(
            [call.kwargs["initialize"] for call in operation.call_args_list],
            [True, False],
        )
        self.assertEqual(operation.call_args_list[0].args[2], "monodoo_core,monodoo_home")
        self.assertEqual(operation.call_args_list[1].args[2], "monodoo_core,monodoo_home")

    def test_existing_database_updates_without_reinitializing_installed_modules(self):
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules="monodoo_core,monodoo_home",
        )
        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(
                migration,
                "psql_scalar",
                return_value="monodoo_core\nmonodoo_home",
            ),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
        ):
            migration.main()

        self.assertEqual(len(operation.call_args_list), 1)
        self.assertFalse(operation.call_args_list[0].kwargs["initialize"])

    def test_odoo_19_without_demo_option_uses_boolean_value(self):
        text = MIGRATION.read_text()
        self.assertIn('"--without-demo=True"', text)
        self.assertNotIn('"--without-demo=all"', text)


if __name__ == "__main__":
    unittest.main()
