import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/classify-release.py"

class ReleaseClassifierTest(unittest.TestCase):
    def classify(self, *paths):
        result = subprocess.run([sys.executable, str(SCRIPT), *paths], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_docs_and_tests_do_not_deploy(self):
        self.assertEqual(self.classify("README.md", "docs/operations.md", "tests/test_x.py")["release_class"], "NO_DEPLOY")

    def test_docker_runtime_change_is_runtime_only(self):
        self.assertEqual(self.classify("docker/Dockerfile")["release_class"], "RUNTIME_ONLY")

    def test_theme_source_is_module_update(self):
        result = self.classify("addons/facodi-theme/theme_facodi/static/src/scss/website.scss")
        self.assertEqual(result["release_class"], "MODULE_UPDATE")
        self.assertEqual(result["update_modules"], ["theme_facodi"])

    def test_manifest_and_migration_changes_require_migration(self):
        for path in (
            "addons/facodi-learning/facodi_learning/__manifest__.py",
            "addons/facodi-theme/theme_facodi/migrations/19.0.1.0/post.py",
            "docker/migrate.py",
            "deploy/coolify/docker-compose.yml",
        ):
            with self.subTest(path=path):
                self.assertEqual(self.classify(path)["release_class"], "MIGRATION_REQUIRED")

    def test_mixed_paths_choose_highest_risk(self):
        result = self.classify("README.md", "docker/Dockerfile", "addons/facodi-learning/facodi_learning/__manifest__.py")
        self.assertEqual(result["release_class"], "MIGRATION_REQUIRED")

    def test_owner_submodule_pointer_is_never_ignored(self):
        result = self.classify("addons/facodi-theme")
        self.assertEqual(result["release_class"], "MIGRATION_REQUIRED")
        self.assertEqual(result["update_modules"], ["theme_facodi"])

    def test_unknown_addon_path_escalates(self):
        self.assertEqual(self.classify("addons/new-addon/file.py")["release_class"], "MIGRATION_REQUIRED")

if __name__ == "__main__":
    unittest.main()
