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


if __name__ == "__main__":
    unittest.main()
