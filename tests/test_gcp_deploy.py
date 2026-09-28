"""The GCP rollout must build first and gate Odoo on a successful migration."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "deploy/gcp/deploy.sh"


class GcpDeployTest(unittest.TestCase):
    def run_deploy(self, *, fail_migration=False, domain="gcp.example.org"):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / ".env").write_text(
                f"FACODI_GCP_DOMAIN={domain}\n"
                "GCP_DB_PASSWORD=example-only\n"
                "GCP_ODOO_ADMIN_PASSWORD=example-only\n"
            )
            fake = work / "bin"
            fake.mkdir()
            (fake / "git").write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *rev-parse*HEAD*) echo 0123456789abcdef0123456789abcdef01234567;;\n"
                "  *status*--porcelain*) :;;\n"
                "  *submodule*status*) echo ' 0123456789abcdef0123456789abcdef01234567 addons/example';;\n"
                "esac\n"
            )
            (fake / "docker").write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$FAKE_DOCKER_LOG\"\n"
                "case \"$*\" in\n"
                "  *'run --rm migrate'*) exit \"${FAIL_MIGRATION:-0}\";;\n"
                "esac\n"
            )
            for executable in fake.iterdir():
                executable.chmod(0o755)
            log = work / "docker.log"
            env = dict(os.environ, PATH=f"{fake}:{os.environ['PATH']}",
                       FAKE_DOCKER_LOG=str(log),
                       FAIL_MIGRATION="1" if fail_migration else "0")
            result = subprocess.run(
                ["bash", str(SCRIPT), str(work / ".env")],
                cwd=ROOT, env=env, capture_output=True, text=True,
            )
            return result, log.read_text().splitlines() if log.exists() else []

    def test_build_precedes_stop_and_successful_migration_precedes_start(self):
        result, calls = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        build = next(i for i, call in enumerate(calls) if call.startswith("build "))
        stop = next(i for i, call in enumerate(calls) if " stop odoo" in call)
        migrate = next(i for i, call in enumerate(calls) if " run --rm migrate" in call)
        start = next(i for i, call in enumerate(calls) if " up -d --no-deps odoo caddy" in call)
        self.assertLess(build, stop)
        self.assertLess(stop, migrate)
        self.assertLess(migrate, start)

    def test_failed_migration_never_starts_odoo(self):
        result, calls = self.run_deploy(fail_migration=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(any(" run --rm migrate" in call for call in calls))
        self.assertFalse(any(" up -d --no-deps odoo caddy" in call for call in calls))

    def test_production_domain_is_rejected_before_any_docker_action(self):
        result, calls = self.run_deploy(domain="facodi.com")
        self.assertEqual(result.returncode, 64)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
