#!/usr/bin/env python3
import json
import sys
from dataclasses import dataclass

RISK = {"NO_DEPLOY": 0, "RUNTIME_ONLY": 1, "MODULE_UPDATE": 2, "MIGRATION_REQUIRED": 3}
OWNERS = {
    "addons/facodi-theme": "theme_facodi",
    "addons/facodi-learning": "facodi_learning",
    "addons/facodi-ai/facodi_ai_website": "facodi_ai_website",
    "addons/facodi-ai": "facodi_ai",
    "addons/muk_web_theme-19.0.1.4.9": "muk_web_theme",
    "addons/onlyoffice_odoo": "onlyoffice_odoo",
}

@dataclass(frozen=True)
class Classification:
    release_class: str
    module: str | None = None

def _owner(path: str) -> str | None:
    for prefix, module in sorted(OWNERS.items(), key=lambda item: len(item[0]), reverse=True):
        if path == prefix or path.startswith(prefix + "/"):
            return module
    return None

def classify_path(path: str) -> Classification:
    path = path.strip().lstrip("./")
    if not path:
        return Classification("NO_DEPLOY")
    if path.startswith(("docs/", "tests/", ".github/")) or path in {"README.md", "AGENTS.md", "PRODUCT.md", "ARCHITECTURE.md"}:
        return Classification("NO_DEPLOY")
    module = _owner(path)
    if module:
        if path in OWNERS:
            return Classification("MIGRATION_REQUIRED", module)
        if "/migrations/" in path or path.endswith("__manifest__.py"):
            return Classification("MIGRATION_REQUIRED", module)
        return Classification("MODULE_UPDATE", module)
    if path.startswith("addons/"):
        return Classification("MIGRATION_REQUIRED")
    if path == "docker/migrate.py" or path == "deploy/coolify/docker-compose.yml":
        return Classification("MIGRATION_REQUIRED")
    if path.startswith("docker/"):
        return Classification("RUNTIME_ONLY")
    if path in {".gitmodules", ".env.ci"}:
        return Classification("MIGRATION_REQUIRED")
    return Classification("RUNTIME_ONLY")

def classify_paths(paths: list[str]) -> dict:
    decisions = [classify_path(path) for path in paths] or [Classification("NO_DEPLOY")]
    release_class = max(decisions, key=lambda d: RISK[d.release_class]).release_class
    modules = sorted({d.module for d in decisions if d.module})
    return {"release_class": release_class, "update_modules": modules}

def main() -> int:
    print(json.dumps(classify_paths(sys.argv[1:]), sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
