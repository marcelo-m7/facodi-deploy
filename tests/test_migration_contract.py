from pathlib import Path
import argparse
import importlib.util
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "docker/migrate.py"
FACODI_MODULES = "facodi_api,facodi_learning,theme_facodi,facodi_ai,facodi_ai_learning,muk_web_theme,monodoo_core,monodoo_home,website_forum,website_slides_forum"


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
            "activate_required_languages",
            "configure_languages",
            "apply_theme",
            "configure_processing_plane",
        ):
            self.assertIn(f"def {name}", text)
        self.assertNotIn("website.page", text)
        self.assertNotIn("website_page", text)

    def test_existing_database_activates_languages_before_module_changes(self):
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules=FACODI_MODULES,
        )
        events = []

        def record_languages(*_args, **_kwargs):
            events.append("languages")

        def record_operation(*_args, **_kwargs):
            events.append("module")

        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(migration, "missing_modules", return_value=""),
            mock.patch.object(migration, "uninstall_retired_modules"),
            mock.patch.object(migration, "activate_required_languages", side_effect=record_languages),
            mock.patch.object(migration, "run_module_operation", side_effect=record_operation),
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        self.assertEqual(events, ["languages", "module"])

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
            mock.patch.object(migration, "activate_required_languages"),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        self.assertEqual(
            [call.kwargs["initialize"] for call in operation.call_args_list],
            [True, False],
        )
        self.assertEqual(
            operation.call_args_list[0].args[2],
            "facodi_api,facodi_ai,facodi_ai_learning,muk_web_theme,monodoo_core,monodoo_home,website_forum,website_slides_forum",
        )
        self.assertEqual(
            operation.call_args_list[1].args[2],
            "facodi_api,facodi_learning,theme_facodi,facodi_ai,facodi_ai_learning,muk_web_theme,monodoo_core,monodoo_home",
        )

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
                return_value="facodi_api\nfacodi_ai\nfacodi_ai_learning\nfacodi_learning\nmonodoo_core\nmonodoo_home\nmuk_web_theme\ntheme_facodi\nwebsite_forum\nwebsite_slides_forum",
            ),
            mock.patch.object(migration, "uninstall_retired_modules"),
            mock.patch.object(migration, "activate_required_languages"),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        self.assertEqual(len(operation.call_args_list), 1)
        self.assertFalse(operation.call_args_list[0].kwargs["initialize"])
        self.assertEqual(
            operation.call_args_list[0].args[2],
            "facodi_api,facodi_learning,theme_facodi,facodi_ai,facodi_ai_learning,muk_web_theme,monodoo_core,monodoo_home",
        )

    def test_existing_database_does_not_reapply_theme(self):
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
            mock.patch.object(migration, "uninstall_retired_modules"),
            mock.patch.object(migration, "activate_required_languages"),
            mock.patch.object(migration, "run_module_operation"),
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme") as apply_theme,
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        apply_theme.assert_not_called()

    def test_existing_database_does_not_force_update_standard_community_modules(self):
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
            mock.patch.object(migration, "uninstall_retired_modules"),
            mock.patch.object(migration, "activate_required_languages"),
            mock.patch.object(migration, "run_module_operation") as operation,
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        updated = operation.call_args.args[2]
        self.assertNotIn("website_forum", updated)
        self.assertNotIn("website_slides_forum", updated)
        self.assertIn("facodi_learning", updated)
        self.assertIn("theme_facodi", updated)

    def test_migration_emits_named_runtime_stages(self):
        text = MIGRATION.read_text()
        self.assertIn("[facodi-migrate]", text)
        self.assertIn("upgrade persisted database", text)
        self.assertIn("update managed modules", text)
        self.assertIn("migration completed successfully", text)

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
            mock.patch.object(migration, "activate_required_languages"),
            mock.patch.object(migration, "run_module_operation"),
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        self.assertEqual(
            uninstall.call_args_list,
            [
                mock.call("/tmp/odoo.conf", "facodi"),
                mock.call("/tmp/odoo.conf", "facodi", post_update=True),
            ],
        )

    def test_theme_common_is_retired_only_after_managed_theme_update(self):
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules=FACODI_MODULES,
        )
        events = []

        def record_uninstall(*_args, **kwargs):
            events.append("retire-post" if kwargs.get("post_update") else "retire-pre")

        def record_update(*_args, **_kwargs):
            events.append("update")

        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=True),
            mock.patch.object(migration, "inspect_legacy_state", return_value="current"),
            mock.patch.object(migration, "missing_modules", return_value=""),
            mock.patch.object(
                migration,
                "uninstall_retired_modules",
                side_effect=record_uninstall,
            ),
            mock.patch.object(migration, "activate_required_languages"),
            mock.patch.object(
                migration,
                "run_module_operation",
                side_effect=record_update,
            ),
            mock.patch.object(migration, "configure_languages"),
            mock.patch.object(migration, "apply_theme"),
            mock.patch.object(migration, "configure_processing_plane"),
        ):
            migration.main()

        self.assertEqual(events, ["retire-pre", "update", "retire-post"])

    def test_post_update_retirement_targets_only_theme_common(self):
        migration = load_migration_module()
        with mock.patch.object(migration, "run_shell") as shell:
            migration.uninstall_retired_modules(
                "/tmp/odoo.conf",
                "facodi",
                post_update=True,
            )

        payload = shell.call_args.args[2]
        self.assertIn("button_immediate_uninstall", payload)
        self.assertIn("theme_common", payload)
        self.assertNotIn("onlyoffice_odoo", payload)
        self.assertNotIn("theme_monynha", payload)

    def test_retired_modules_use_standard_odoo_uninstall_api(self):
        migration = load_migration_module()
        with mock.patch.object(migration, "run_shell") as shell:
            migration.uninstall_retired_modules("/tmp/odoo.conf", "facodi")

        payload = shell.call_args.args[2]
        self.assertIn("button_immediate_uninstall", payload)
        self.assertIn("onlyoffice_odoo", payload)
        self.assertIn("monodoo_backend", payload)
        self.assertNotIn('"monodoo_core"', payload)
        self.assertNotIn('"monodoo_home"', payload)
        self.assertIn("theme_monynha", payload)

    def test_deploy_does_not_reconcile_editor_managed_navigation(self):
        text = MIGRATION.read_text()
        self.assertNotIn("def normalize_public_navigation", text)
        self.assertNotIn("facodi_reconcile_navigation", text)

    def test_fresh_or_domainless_single_website_is_an_unambiguous_bootstrap(self):
        migration = load_migration_module()

        fresh_payload = migration._website_selector_payload(fresh_database=True)
        self.assertIn("fresh_database = True", fresh_payload)
        self.assertIn("or not normalize_domain(websites.domain)", fresh_payload)

        existing_payload = migration._website_selector_payload(fresh_database=False)
        self.assertIn("fresh_database = False", existing_payload)
        self.assertIn("len(websites) == 1", existing_payload)
        self.assertIn("or not normalize_domain(websites.domain)", existing_payload)

    def test_main_propagates_fresh_database_state_to_website_phases(self):
        migration = load_migration_module()
        args = argparse.Namespace(
            config="/tmp/odoo.conf",
            database="facodi",
            modules=FACODI_MODULES,
        )
        with (
            mock.patch.object(migration, "parse_args", return_value=args),
            mock.patch.object(migration, "registry_exists", return_value=False),
            mock.patch.object(migration, "run_module_operation"),
            mock.patch.object(migration, "configure_languages") as configure,
            mock.patch.object(migration, "apply_theme") as apply_theme,
            mock.patch.object(migration, "configure_processing_plane") as processing,
        ):
            migration.main()

        configure.assert_called_once_with(
            "/tmp/odoo.conf", "facodi", fresh_database=True
        )
        apply_theme.assert_called_once_with(
            "/tmp/odoo.conf", "facodi", fresh_database=True
        )
        processing.assert_called_once_with("/tmp/odoo.conf", "facodi")

    def test_configure_languages_refreshes_both_public_modules(self):
        migration = load_migration_module()
        with mock.patch.object(migration, "run_shell") as shell:
            migration.configure_languages("/tmp/odoo.conf", "facodi")

        payload = shell.call_args.args[2]
        compile(migration.textwrap.dedent(payload), "<facodi-languages>", "exec")
        self.assertIn('for module_name in ("theme_facodi", "facodi_learning")', payload)
        self.assertIn('module._update_translations(["pt_PT", "es_ES", "fr_FR"])', payload)

    def test_processing_plane_configuration_is_fail_closed_and_selects_supabase(self):
        migration = load_migration_module()
        with mock.patch.object(migration, "run_shell") as shell:
            migration.configure_processing_plane("/tmp/odoo.conf", "facodi")

        payload = shell.call_args.args[2]
        compile(
            migration.textwrap.dedent(payload),
            "<facodi-processing-plane>",
            "exec",
        )
        self.assertIn("SUPABASE_URL", payload)
        self.assertIn("SUPABASE_SECRET_KEY", payload)
        self.assertIn("must be configured together", payload)
        self.assertIn('parsed.scheme.lower() != "https"', payload)
        self.assertIn('parsed.username', payload)
        self.assertIn('parsed.password', payload)
        self.assertIn('port not in (None, 443)', payload)
        self.assertIn('parsed.path not in ("", "/")', payload)
        self.assertIn('parsed.query', payload)
        self.assertIn('parsed.fragment', payload)
        self.assertIn(
            'params.set_param("facodi_learning.analysis_provider", "local_metadata")',
            payload,
        )
        self.assertIn(
            'params.set_param("facodi_learning.processing_plane", "local")',
            payload,
        )
        self.assertIn(
            'params.set_param("facodi_learning.analysis_provider", "supabase_edge")',
            payload,
        )
        self.assertIn(
            'params.set_param("facodi_learning.processing_plane", "supabase")',
            payload,
        )

    def test_processing_plane_configuration_runs_after_theme(self):
        text = MIGRATION.read_text()
        self.assertLess(
            text.rindex("apply_theme("),
            text.rindex("configure_processing_plane("),
        )

    def test_native_adapter_gate_runs_before_runtime_start(self):
        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        adapter = runtime.index("--test-tags facodi_api_consumers")
        start = runtime.index('"${compose[@]}" up -d odoo')
        self.assertLess(adapter, start)

    def test_odoo_19_without_demo_option_uses_boolean_value(self):
        text = MIGRATION.read_text()
        self.assertIn('"--without-demo=True"', text)
        self.assertNotIn('"--without-demo=all"', text)


if __name__ == "__main__":
    unittest.main()
