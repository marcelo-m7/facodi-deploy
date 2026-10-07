"""Execute the actual migration shell payload against a tiny configuration store."""
import os
import textwrap
import unittest
from unittest.mock import patch

from test_migration_contract import load_migration_module


class Params:
    def __init__(self, provider):
        self.values = {'facodi_learning.analysis_provider': provider,
                       'facodi_api.pipeline_enabled': 'false'}

    def sudo(self):
        return self

    def get_param(self, key, default=False):
        return self.values.get(key, default)

    def set_param(self, key, value):
        self.values[key] = value


class Modules:
    def __init__(self, api_installed=True):
        self.api_installed = api_installed

    def search(self, domain, limit=1):
        name = next(value for field, operator, value in domain if field == 'name')
        return name == 'facodi_learning' or (name == 'facodi_api' and self.api_installed)


class Env:
    def __init__(self, provider, api_installed=True):
        self.params = Params(provider)
        self.modules = Modules(api_installed)
        self.commits = 0
        self.cr = self

    def __getitem__(self, key):
        return {'ir.config_parameter': self.params, 'ir.module.module': self.modules}[key]

    def commit(self):
        self.commits += 1


class ProcessingPlaneBehavior(unittest.TestCase):
    def execute(self, env, variables):
        migration = load_migration_module()
        with patch.object(migration, 'run_shell') as shell:
            migration.configure_processing_plane('/tmp/odoo.conf', 'facodi')
        with patch.dict(os.environ, variables, clear=True):
            exec(compile(textwrap.dedent(shell.call_args.args[2]), '<migration>', 'exec'), {'env': env})

    def test_opt_in_provider_survives_repeated_migrations_and_legacy_secret_changes(self):
        for variables in ({}, {'SUPABASE_URL': 'https://example.supabase.co', 'SUPABASE_SECRET_KEY': 'fixture'},
                          {'SUPABASE_URL': 'malformed-unused-legacy-origin'}):
            env = Env('odoo_python')
            self.execute(env, variables)
            self.execute(env, variables)
            self.assertEqual(env.params.values['facodi_learning.analysis_provider'], 'odoo_python')
            self.assertEqual(env.params.values['facodi_learning.processing_plane'], 'odoo_python')
            self.assertEqual(env.params.values['facodi_api.pipeline_enabled'], 'false')
            self.assertEqual(env.commits, 2)

    def test_local_selection_without_installed_engine_fails_closed(self):
        env = Env('odoo_python', api_installed=False)
        with self.assertRaisesRegex(RuntimeError, 'facodi_api'):
            self.execute(env, {})
        self.assertEqual(env.commits, 0)

    def test_legacy_partial_pair_remains_a_configuration_failure(self):
        with self.assertRaisesRegex(RuntimeError, 'configured together'):
            self.execute(Env('supabase_edge'), {'SUPABASE_URL': 'https://example.supabase.co'})

    def test_legacy_without_credentials_still_uses_safe_metadata_fallback(self):
        env = Env('supabase_edge')
        self.execute(env, {})
        self.assertEqual(env.params.values['facodi_learning.analysis_provider'], 'local_metadata')
