from pathlib import Path
import argparse
import importlib.util
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "docker/migrate.py"
FACODI_MODULES = "facodi_learning,theme_facodi,facodi_ai,facodi_ai_website"


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
            "uninstall_retired_modules",
            "run_module_operation",
            "configure_languages",
            "apply_theme",
            "normalize_public_navigation",
        ):
            self.assertIn(f"def {name}", text)
        self.assertNotIn("website.page", text)
        self.assertNotIn("website_page", text)

    def test_existing_database_initializes_required_modules_before_update(self):
        """New FACODI capabilities must install on an already-existing database."""
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules=FACODI_MODULES,
        )
        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(migration, "psql_scalar", return_value="facodi_learning\ntheme_facodi"),
            mock.patch.object(migration, "uninstall_retired_modules"),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "normalize_public_navigation"),
        ):
            migration.main()

        self.assertEqual(
            [call.kwargs["initialize"] for call in operation.call_args_list],
            [True, False],
        )
        self.assertEqual(
            operation.call_args_list[0].args[2],
            "facodi_ai,facodi_ai_website",
        )
        self.assertEqual(operation.call_args_list[1].args[2], FACODI_MODULES)

    def test_existing_database_updates_without_reinitializing_installed_modules(self):
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules=FACODI_MODULES,
        )
        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(
                migration,
                "psql_scalar",
                return_value="facodi_ai\nfacodi_ai_website\nfacodi_learning\ntheme_facodi",
            ),
            mock.patch.object(migration, "uninstall_retired_modules"),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "normalize_public_navigation"),
        ):
            migration.main()

        self.assertEqual(len(operation.call_args_list), 1)
        self.assertFalse(operation.call_args_list[0].kwargs["initialize"])
        self.assertEqual(operation.call_args_list[0].args[2], FACODI_MODULES)

    def test_existing_database_uninstalls_retired_modules_before_update(self):
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules=FACODI_MODULES,
        )
        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(migration, "missing_modules", return_value=""),
            mock.patch.object(migration, "uninstall_retired_modules") as uninstall,
            mock.patch.object(migration, "run_module_operation"),
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "normalize_public_navigation"),
        ):
            migration.main()

        uninstall.assert_called_once_with("/tmp/odoo.conf", "facodi")

    def test_retired_modules_use_standard_odoo_uninstall_api(self):
        migration = load_migration_module()
        with mock.patch.object(migration, "run_shell") as shell:
            migration.uninstall_retired_modules("/tmp/odoo.conf", "facodi")

        payload = shell.call_args.args[2]
        self.assertIn("button_immediate_uninstall", payload)
        self.assertIn("monodoo_backend", payload)
        self.assertIn("theme_monynha", payload)

    def test_navigation_normalization_is_website_scoped_and_runs_after_theme(self):
        text = MIGRATION.read_text()
        self.assertIn('("website_id", "=", facodi_website.id)', text)
        self.assertIn('("url", "in", ["/roadmap", "/mapa-curricular", "/curriculos"])', text)
        self.assertIn('canonical.write({"name": "Roadmaps", "url": "/roadmaps"})', text)
        self.assertIn("(legacy - canonical).unlink()", text)
        self.assertLess(
            text.index("apply_theme(args.config, args.database)"),
            text.index("normalize_public_navigation(args.config, args.database)"),
        )

    def test_odoo_19_without_demo_option_uses_boolean_value(self):
        text = MIGRATION.read_text()
        self.assertIn('"--without-demo=True"', text)
        self.assertNotIn('"--without-demo=all"', text)


if __name__ == "__main__":
    unittest.main()
