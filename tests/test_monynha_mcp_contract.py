"""Fast fail-closed source contract for independent Monynha services."""

import ast
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
FACODI_COMPOSE = ROOT / "deploy/coolify/docker-compose.yml"
MCP_COMPOSE = ROOT / "deploy/coolify/monynha-mcp.compose.yml"


class MonynhaCoolifyContract(unittest.TestCase):
    def test_separate_mcp_compose_does_not_modify_odoo_persistence(self):
        facodi = FACODI_COMPOSE.read_text()
        source = MCP_COMPOSE.read_text()
        self.assertIn("  monynha-db:\n", source)
        self.assertIn("  monynha-mcp:\n", source)
        self.assertNotIn("monynha-db:", facodi)
        self.assertNotIn("monynha-mcp:", facodi)
        self.assertIn("postgres-data:/var/lib/postgresql/data", facodi)
        self.assertIn("odoo-data:/var/lib/odoo", facodi)
        self.assertIn("monynha-postgres-data:/var/lib/postgresql/data", source)
        self.assertNotIn("odoo-data:/var/lib/odoo", source)
        self.assertNotIn("profiles:", source)
        self.assertIn("monynha-private:", source)
        self.assertIn("internal: true", source)
        self.assertNotIn('8000:8000', source)
        self.assertNotIn('5432:5432', source)

    def test_mcp_uses_pinned_source_and_read_only_supabase_security_defaults(self):
        source = MCP_COMPOSE.read_text()
        self.assertRegex(source, r"https://github\.com/marcelo-m7/odoo-remote-mcp\.git#[0-9a-f]{40}")
        self.assertIn("MONYNHA_MCP_OAUTH_PROVIDER: supabase", source)
        self.assertIn("MONYNHA_MCP_OAUTH_ALLOWED_CLIENT_IDS: ${MONYNHA_MCP_OAUTH_ALLOWED_CLIENT_IDS:-[]}", source)
        self.assertIn("MONYNHA_MCP_WRITES_ENABLED: \"false\"", source)
        self.assertIn("MONYNHA_MCP_OIDC_AUDIENCE: ${MONYNHA_MCP_PUBLIC_URL:?", source)
        self.assertIn("MONYNHA_MCP_DATABASE_URL: ${MONYNHA_MCP_DATABASE_URL:?", source)
        self.assertIn("POSTGRES_PASSWORD: ${MONYNHA_MCP_DB_PASSWORD:?", source)
        self.assertIn("MONYNHA_MCP_OIDC_ISSUER: https://wvkjainfwsyiyfcmbtid.supabase.co/auth/v1", source)
        self.assertIn("8000/readyz", source)
        self.assertIn("read_only: true", source)
        self.assertIn("no-new-privileges:true", source)

    def test_consent_addon_installed_by_both_migrate_and_odoo(self):
        source = FACODI_COMPOSE.read_text()
        self.assertEqual(len(re.findall(r"FACODI_MODULES: [^\n]*facodi_mcp_oauth", source)), 2)
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        self.assertIn("website_slides_forum,facodi_mcp_oauth", entrypoint)
        self.assertGreaterEqual(source.count("MONYNHA_OAUTH_SUPABASE_PUBLISHABLE_KEY:"), 2)
        self.assertGreaterEqual(source.count("MONYNHA_OAUTH_ALLOWED_CLIENT_IDS:"), 2)

    def test_new_addon_stays_under_original_api_source_gitlink(self):
        manifest_path = ROOT / "addons/facodi-api/facodi_mcp_oauth/__manifest__.py"
        manifest = ast.literal_eval(manifest_path.read_text())
        self.assertEqual(manifest["depends"], ["website"])
        self.assertTrue(manifest["installable"])


if __name__ == "__main__":
    unittest.main()
