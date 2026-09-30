from pathlib import Path
import ast
import configparser
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]

EXPECTED_SUBMODULE_PATHS = {
    "addons/facodi-ai",
    "addons/facodi-learning",
    "addons/facodi-theme",
    "addons/muk_web_theme-19.0.1.4.9",
    "addons/monodoo",
    "vendor/odoo-design-themes",
}

FACODI_MODULES = "facodi_learning,theme_facodi,facodi_ai,facodi_ai_website,muk_web_theme,monodoo_core,monodoo_home,website_forum,website_slides_forum"


class RepositoryContractTest(unittest.TestCase):
    def test_submodules_and_modules(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".gitmodules")
        paths = {parser[s]["path"] for s in parser.sections()}
        self.assertEqual(paths, EXPECTED_SUBMODULE_PATHS)

        tree = subprocess.check_output(
            ["git", "-C", str(ROOT), "ls-tree", "-r", "HEAD"], text=True
        )
        gitlinks = {
            line.split("\t", 1)[1]
            for line in tree.splitlines()
            if line.startswith("160000 commit ")
        }
        self.assertEqual(
            gitlinks,
            EXPECTED_SUBMODULE_PATHS,
            "Every gitlink must be declared by the canonical submodule contract",
        )
        self.assertTrue((ROOT / "addons/facodi-ai/facodi_ai/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-ai/facodi_ai_website/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-ai/requirements.txt").is_file())
        self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/muk_web_theme-19.0.1.4.9/muk_web_theme/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monodoo/monodoo_core/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/monodoo/monodoo_home/__manifest__.py").is_file())
        self.assertTrue((ROOT / "vendor/odoo-design-themes/theme_common/__manifest__.py").is_file())

    def test_exact_integration_pins_match_superproject_gitlinks(self):
        """The superproject gitlink is the single source of truth for every pin."""
        for path in sorted(EXPECTED_SUBMODULE_PATHS):
            tree_line = subprocess.check_output(
                ["git", "-C", str(ROOT), "ls-tree", "HEAD", path], text=True
            ).strip()
            self.assertTrue(tree_line, path)
            mode_type_sha, _ = tree_line.split("\t", 1)
            mode, object_type, expected = mode_type_sha.split()
            self.assertEqual(mode, "160000", path)
            self.assertEqual(object_type, "commit", path)
            actual = subprocess.check_output(
                ["git", "-C", str(ROOT / path), "rev-parse", "HEAD"], text=True
            ).strip()
            self.assertEqual(actual, expected, path)

    def test_contextual_contribution_safe_projection_contract(self):
        learning_root = ROOT / "addons/facodi-learning/facodi_learning"
        theme_root = ROOT / "addons/facodi-theme/theme_facodi"

        controller = (learning_root / "controllers/submission.py").read_text()
        model = (learning_root / "models/contextual_submission.py").read_text()
        view = (learning_root / "views/website_submission.xml").read_text()
        styles = (theme_root / "static/src/scss/enriched_surfaces.scss").read_text()

        self.assertIn("_facodi_contributor_context_rows", controller)
        self.assertIn("_facodi_contributor_context_rows", model)
        self.assertGreaterEqual(view.count('data-facodi-captured-context="1"'), 2)
        self.assertNotIn('t-esc="submission.source_page_url"', view)
        self.assertIn(".facodi-captured-context", styles)
        self.assertIn('minmax(#{"min(100%, 12rem)"}, 1fr)', styles)

        controller_context = (learning_root / "controllers/contextual_submission.py").read_text()
        faq = (theme_root / "views/snippets/s_facodi_faq.xml").read_text()
        forum_postit = (
            theme_root / "views/snippets/components/s_facodi_forum_postit.xml"
        ).read_text()
        self.assertIn('"faq_contact_cta": "collaboration"', controller_context)
        self.assertIn('"forum_postit_contact_cta": "collaboration"', controller_context)
        self.assertIn("source=faq_contact_cta", faq)
        self.assertIn("source=forum_postit_contact_cta", forum_postit)

    def test_public_contextual_ctas_have_human_provenance_labels(self):
        learning_root = ROOT / "addons/facodi-learning/facodi_learning"
        theme_root = ROOT / "addons/facodi-theme/theme_facodi"

        model_source = (learning_root / "models/contextual_submission.py").read_text()
        model_tree = ast.parse(model_source)
        registry_keys = set()
        for node in model_tree.body:
            if isinstance(node, ast.Assign) and any(
                isinstance(target, ast.Name) and target.id == "_SOURCE_CTA_LABELS"
                for target in node.targets
            ):
                self.assertIsInstance(node.value, ast.Dict)
                registry_keys = {
                    key.value
                    for key in node.value.keys
                    if isinstance(key, ast.Constant) and isinstance(key.value, str)
                }
                break
        self.assertTrue(registry_keys, "_SOURCE_CTA_LABELS registry is missing")

        public_sources = set()
        source_in_url = re.compile(r"source=([a-z0-9][a-z0-9_-]{0,63})")
        source_mapping = re.compile(
            r"""["']source["']\s*:\s*["']([a-z0-9][a-z0-9_-]{0,63})["']"""
        )
        for root in (learning_root / "views", theme_root / "views"):
            for xml_path in root.rglob("*.xml"):
                public_sources.update(source_in_url.findall(xml_path.read_text()))
        for py_path in (
            learning_root / "controllers",
            learning_root / "models",
        ):
            for source_path in py_path.rglob("*.py"):
                source = source_path.read_text()
                public_sources.update(source_in_url.findall(source))
                public_sources.update(source_mapping.findall(source))

        missing = sorted(public_sources - registry_keys)
        self.assertFalse(
            missing,
            "Public contextual CTA source(s) lack a human provenance label: "
            + ", ".join(missing),
        )

    def test_public_contextual_sections_have_human_labels(self):
        learning_root = ROOT / "addons/facodi-learning/facodi_learning"
        theme_root = ROOT / "addons/facodi-theme/theme_facodi"

        controller_source = (
            learning_root / "controllers/contextual_submission.py"
        ).read_text()
        controller_tree = ast.parse(controller_source)
        section_keys = set()
        for node in ast.walk(controller_tree):
            if isinstance(node, ast.Assign) and any(
                isinstance(target, ast.Name) and target.id == "section_labels"
                for target in node.targets
            ):
                self.assertIsInstance(node.value, ast.Dict)
                section_keys = {
                    key.value
                    for key in node.value.keys
                    if isinstance(key, ast.Constant) and isinstance(key.value, str)
                }
                break
        self.assertTrue(section_keys, "section_labels registry is missing")

        public_sections = set()
        section_in_url = re.compile(r"section=([a-z0-9][a-z0-9_-]{0,63})")
        section_mapping = re.compile(
            r"""["']section["']\s*:\s*["']([a-z0-9][a-z0-9_-]{0,63})["']"""
        )
        for root in (learning_root / "views", theme_root / "views"):
            for xml_path in root.rglob("*.xml"):
                public_sections.update(section_in_url.findall(xml_path.read_text()))
        for py_root in (
            learning_root / "controllers",
            learning_root / "models",
        ):
            for source_path in py_root.rglob("*.py"):
                source = source_path.read_text()
                public_sections.update(section_in_url.findall(source))
                public_sections.update(section_mapping.findall(source))

        missing = sorted(public_sections - section_keys)
        self.assertFalse(
            missing,
            "Public contextual section(s) lack a human label: " + ", ".join(missing),
        )

    def test_contextual_forum_and_native_next_tab_contract(self):
        learning_root = ROOT / "addons/facodi-learning/facodi_learning"
        theme_root = ROOT / "addons/facodi-theme/theme_facodi"

        manifest = (learning_root / "__manifest__.py").read_text()
        community = (learning_root / "controllers/community.py").read_text()
        portal = (learning_root / "controllers/portal.py").read_text()
        portal_view = (learning_root / "views/portal_home.xml").read_text()
        portal_styles = (theme_root / "static/src/scss/portal.scss").read_text()

        self.assertIn('"website_forum"', manifest)
        self.assertIn('"/community/new"', community)
        self.assertIn('/ask?', community)
        self.assertIn('{"question", "share"}', community)
        self.assertIn("next_slide_id", portal)
        self.assertIn('"continue_url"', portal)
        self.assertIn('data-facodi-next-tab="1"', portal_view)
        self.assertIn(".facodi-portal-next-tab", portal_styles)

    def test_d1_learning_interfaces_browser_acceptance_contract(self):
        theme_manifest = (ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").read_text()
        learning_manifest = (ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").read_text()

        portal_controller = (
            ROOT / "addons/facodi-learning/facodi_learning/controllers/portal.py"
        ).read_text()
        self.assertIn(
            'return request.redirect("/my/home", code=301)',
            portal_controller,
        )

        browser = ROOT / "tests/test_campus_paper_browser.mjs"
        self.assertTrue(browser.is_file(), str(browser))
        browser_source = browser.read_text()
        for marker in (
            "facodi-learning-catalogue-hero",
            "facodi-course-study-shell",
            "facodi-roadmap-study-path",
            "facodi-filter-sheet",
            "facodi-unit-layout",
            "facodi-module-detail",
            'data-facodi-explore-workbench="1"',
            'data-facodi-portal-home="1"',
            "facodi-portal-board",
            'data-facodi-academic-map="1"',
            'data-facodi-campus-pulse="1"',
            '[data-facodi-submission-form="1"]',
            '[data-facodi-contribution-brief="1"]',
            "unit_resource_cta",
            "faq_contact_cta",
            "contextual-resource-intake-mobile.png",
            "contextual-faq-contact-mobile.png",
            "backend-monodoo-home-muk-desktop.png",
            ".o_monodoo_home",
            ".facodi-portal-toolbox-heading",
            "permanent 301",
            "maxRedirects: 0",
            "\"/minha-facodi\"",
            "document.documentElement.scrollWidth",
            "window.innerWidth",
        ):
            self.assertIn(marker, browser_source)

        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        self.assertIn("FACODI_BROWSER_ACCEPTANCE", runtime)
        self.assertIn("tests/test_campus_paper_browser.mjs", runtime)
        for variable in (
            "FACODI_BROWSER_COURSE_ROUTE",
            "FACODI_BROWSER_ROADMAP_ROUTE",
            "FACODI_BROWSER_UNIT_ROUTE",
            "FACODI_BROWSER_MODULE_ROUTE",
        ):
            self.assertIn(variable, runtime)

        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("actions/setup-node@v4", workflow)
        self.assertIn("playwright-core@1.55.0", workflow)
        self.assertIn("FACODI_BROWSER_ACCEPTANCE", workflow)
        self.assertIn("facodi-browser-acceptance", workflow)
        self.assertIn("actions/upload-artifact@v4", workflow)

    def test_d2_editorial_public_pages_browser_acceptance_contract(self):
        theme_manifest = (ROOT / "addons/facodi-theme/theme_facodi/__manifest__.py").read_text()
        self.assertIn('"website_blog"', theme_manifest)

        fixture = ROOT / "tests/ci_seed_d2_editorial_runtime.py"
        browser = ROOT / "tests/test_d2_editorial_browser.mjs"
        runtime_gate = ROOT / "tests/test_d2_editorial_runtime.sh"
        for path in (fixture, browser, runtime_gate):
            self.assertTrue(path.is_file(), str(path))

        browser_source = browser.read_text()
        for marker in (
            "facodi-project-story",
            "facodi-principles-ledger",
            "facodi-contribution-board",
            "facodi-blog-index",
            "facodi-bulletin-card",
            "facodi-blog-article",
            "facodi-contact-page",
            "facodi-contact-form-sheet",
            "facodi-policy-document",
            "document.documentElement.scrollWidth",
            "window.innerWidth + 1",
        ):
            self.assertIn(marker, browser_source)

        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        self.assertIn('bash tests/test_d2_editorial_runtime.sh "$project"', runtime)

        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("FACODI_D2_BROWSER_SCREENSHOT_DIR", workflow)
        self.assertIn("facodi-d2-browser-acceptance", workflow)

    def test_permanent_editorial_redirect_release_contract(self):
        theme_root = ROOT / "addons/facodi-theme"
        manifest = (theme_root / "theme_facodi/__manifest__.py").read_text()

        redirect_data = theme_root / "theme_facodi/data/website_rewrites.xml"
        redirect_migration = (
            theme_root
            / "theme_facodi/migrations/19.0.10.1.0/post-10-permanent-editorial-redirects.py"
        )
        self.assertTrue(redirect_data.is_file(), str(redirect_data))
        self.assertTrue(redirect_migration.is_file(), str(redirect_migration))

        source = redirect_data.read_text()
        for old, new in (
            ("/facodi", "/"),
            ("/sobre", "/about"),
            ("/manifesto", "/about"),
            ("/comunidade", "/about"),
            ("/parceiros", "/about"),
            ("/roadmap", "/about#how-it-works"),
            ("/como-contribuir", "/contribuir/recurso"),
            ("/contribuir", "/contribuir/recurso"),
        ):
            self.assertIn(f"<field name=\"url_from\">{old}</field>", source)
            self.assertIn(f"<field name=\"url_to\">{new}</field>", source)
        self.assertEqual(source.count('<field name="redirect_type">301</field>'), 8)
        self.assertNotIn('<field name="url_from">/roadmaps</field>', source)
        self.assertNotIn('<field name="url_from">/contribuir/recurso</field>', source)

        website_scss = (
            theme_root / "theme_facodi/static/src/scss/website.scss"
        ).read_text()
        self.assertIn("background-color: #0B1325 !important", website_scss)
        self.assertIn("background: #0B1325", website_scss)

    def test_facodi_500_surface_is_fail_safe(self):
        error_view = ROOT / "addons/facodi-theme/theme_facodi/views/http_error.xml"
        self.assertTrue(error_view.is_file(), str(error_view))
        source = error_view.read_text()
        self.assertIn('inherit_id="http_routing.500"', source)
        self.assertIn("facodi-error-sheet", source)
        self.assertIn("http_routing.http_error_debug", source)
        self.assertNotIn("website.layout", source)

    def test_dockerfile_bakes_only_required_odoo_modules(self):
        dockerfile = (ROOT / "docker/Dockerfile").read_text()
        self.assertIn("FROM odoo:19.0", dockerfile)
        self.assertIn("COPY addons/ /opt/facodi-addon-sources/", dockerfile)
        self.assertIn(
            "COPY vendor/odoo-design-themes/theme_common/ /opt/theme-common/theme_common/",
            dockerfile,
        )
        self.assertNotIn("COPY vendor/odoo-design-themes/ /", dockerfile)
        self.assertIn("monodoo_core|monodoo_home", dockerfile)
        self.assertIn("/opt/facodi-addon-sources/monodoo/*", dockerfile)

    def test_dockerfile_installs_facodi_ai_python_runtime(self):
        dockerfile = (ROOT / "docker/Dockerfile").read_text()
        self.assertIn("python3-venv", dockerfile)
        self.assertIn("/opt/facodi-addon-sources/facodi-ai/requirements.txt", dockerfile)
        self.assertIn("pydantic_ai", dockerfile)
        self.assertIn("PyJWT", dockerfile)
        self.assertIn("/opt/facodi-venv", dockerfile)

    def test_facodi_modules_are_auto_installed_and_runtime_secret_is_forwarded(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        self.assertGreaterEqual(compose.count(f"FACODI_MODULES: {FACODI_MODULES}"), 2)
        self.assertIn(f'FACODI_MODULES:={FACODI_MODULES}', entrypoint)
        self.assertGreaterEqual(compose.count("GEMINI_API_KEY: ${GEMINI_API_KEY:-}"), 2)
        for variable in (
            "SUPABASE_URL",
            "SUPABASE_SECRET_KEY",
            "SUPABASE_PUBLISHABLE_KEY",
            "SUPABASE_JWKS_URL",
        ):
            self.assertGreaterEqual(
                compose.count(f"{variable}: ${{{variable}:-}}"),
                2,
            )

    def test_standard_forum_modules_are_explicit_runtime_capabilities(self):
        self.assertIn("website_forum", FACODI_MODULES.split(","))
        self.assertIn("website_slides_forum", FACODI_MODULES.split(","))

    def test_monodoo_home_coexists_with_muk_without_monodoo_theme(self):
        modules = FACODI_MODULES.split(",")
        self.assertIn("muk_web_theme", modules)
        self.assertIn("monodoo_core", modules)
        self.assertIn("monodoo_home", modules)
        for module in (
            "monodoo_theme",
            "monodoo_backend",
            "monodoo_appsbar",
            "monodoo_views",
            "monodoo_chatter",
            "monodoo_dialog",
            "onlyoffice_odoo",
        ):
            self.assertNotIn(module, modules)

        home_manifest = ast.literal_eval(
            (ROOT / "addons/monodoo/monodoo_home/__manifest__.py").read_text()
        )
        self.assertEqual(home_manifest["depends"], ["web", "monodoo_core"])
        home_style = (
            ROOT / "addons/monodoo/monodoo_home/static/src/home/home.scss"
        ).read_text()
        self.assertIn("var(--monodoo-bg, var(--bs-body-bg, #fff))", home_style)

    def test_removed_addon_sources_are_not_present_in_runtime_contract(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        entrypoint = (ROOT / "docker/entrypoint.sh").read_text()
        for module in ("onlyoffice_odoo", "monynha", "monodoo_theme"):
            self.assertNotIn(module, compose)
            self.assertNotIn(module, entrypoint)
        self.assertFalse((ROOT / "addons/onlyoffice_odoo").exists())

    def test_generated_local_state_is_ignored(self):
        ignored = (ROOT / ".gitignore").read_text()
        for pattern in (
            "gha-creds-*.json",
            ".env",
            ".env.*",
            "!.env.example",
            "!.env.ci",
            "__pycache__/",
        ):
            self.assertIn(pattern, ignored)
        for obsolete in ("*.tfstate", "*.tfstate.*", ".terraform/"):
            self.assertNotIn(obsolete, ignored)

    def test_coolify_compose_maps_generated_secrets(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertGreaterEqual(compose.count("$SERVICE_PASSWORD_64_POSTGRES"), 3)
        self.assertGreaterEqual(compose.count("$SERVICE_PASSWORD_64_ODOO_ADMIN"), 2)
        self.assertNotIn("${POSTGRES_PASSWORD}", compose)
        self.assertNotIn("${ODOO_ADMIN_PASSWD}", compose)

    def test_coolify_preview_uses_generated_database_service_name(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertGreaterEqual(
            compose.count("DB_HOST: ${SERVICE_NAME_DB:-db}"),
            2,
        )
        self.assertNotIn("DB_HOST: db\n", compose)

    def test_coolify_compose_preserves_persistent_names_and_gates_odoo(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertIn("  db:\n", compose)
        self.assertIn("  migrate:\n", compose)
        self.assertIn("  odoo:\n", compose)
        self.assertIn("postgres-data:/var/lib/postgresql/data", compose)
        self.assertGreaterEqual(compose.count("odoo-data:/var/lib/odoo"), 2)
        self.assertIn("condition: service_completed_successfully", compose)
        self.assertIn('restart: "no"', compose)
        self.assertNotIn("name: facodi-postgres", compose)
        self.assertNotIn("name: facodi-odoo", compose)
        self.assertNotIn("5432:5432", compose)
        self.assertNotIn("8069:8069", compose)

    def test_coolify_compose_checks_odoo_http_health(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        self.assertIn("http://127.0.0.1:$${PORT}/web/login", compose)
        self.assertIn("start_period: 60s", compose)

    def test_coolify_build_context_matches_project_directory(self):
        compose = (ROOT / "deploy/coolify/docker-compose.yml").read_text()
        runtime_test = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        self.assertGreaterEqual(compose.count("context: ."), 2)
        self.assertNotIn("context: ../..", compose)
        self.assertIn('--project-directory "$root"', runtime_test)

    def test_obsolete_google_runtime_is_not_active(self):
        forbidden = [
            ROOT / "infrastructure/terraform",
            ROOT / ".github/workflows/build-image.yml",
            ROOT / ".github/workflows/terraform-plan.yml",
            ROOT / ".github/workflows/terraform-apply.yml",
            ROOT / ".github/workflows/deploy-staging.yml",
            ROOT / ".github/workflows/deploy-production.yml",
            ROOT / "scripts/deploy-runtime.sh",
            ROOT / "scripts/configure-database-user.sh",
            ROOT / "scripts/verify-runtime.sh",
            ROOT / "docs/superpowers/plans/2026-09-05-facodi-deploy-cloud-run-terraform.md",
            ROOT / "docs/superpowers/specs/2026-09-05-facodi-deploy-cloud-run-terraform-design.md",
        ]
        for path in forbidden:
            self.assertFalse(path.exists(), str(path))

    def test_embedded_runtime_python_is_syntactically_valid(self):
        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        blocks = re.findall(
            r"python3\s+-\s+<<'PY'\n(.*?)\nPY(?:\n|$)",
            runtime,
            flags=re.DOTALL,
        )
        self.assertTrue(blocks, "runtime gate must contain embedded Python acceptance")
        for index, source in enumerate(blocks, start=1):
            try:
                ast.parse(source, filename=f"test_coolify_runtime.sh:python-{index}")
            except SyntaxError as exc:
                self.fail(f"embedded Python block {index} does not compile: {exc}")

    def test_clean_install_preflight_waits_for_database_health(self):
        runtime = (ROOT / "tests/test_coolify_runtime.sh").read_text()
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
        self.assertIn("FACODI_REQUIRE_EMPTY_DATABASE", workflow)
        self.assertIn("db_container_id=", runtime)
        self.assertIn(".State.Health.Status", runtime)
        self.assertIn('db_health" != "healthy"', runtime)
        self.assertLess(
            runtime.index("PASS PostgreSQL is healthy before clean-install preflight"),
            runtime.index("Clean-install gate expected no pre-existing facodi database"),
        )

    def test_ci_validates_the_canonical_coolify_runtime(self):
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
        self.assertIn("submodules: recursive", workflow)
        self.assertIn("deploy/coolify/docker-compose.yml", workflow)
        self.assertIn("tests/test_coolify_runtime.sh", workflow)
        self.assertNotIn("terraform", workflow.lower())
        self.assertNotIn("google-github-actions", workflow)

    def test_docs_describe_coolify_as_the_only_runtime(self):
        readme = (ROOT / "README.md").read_text()
        operations = (ROOT / "docs/operations.md").read_text()
        for text in (readme, operations):
            self.assertIn("Coolify", text)
            self.assertIn("facodi.com", text)
            self.assertIn("postgres-data", text)
            self.assertIn("odoo-data", text)
            self.assertIn("v0.1.0", text)
        self.assertNotIn("Cloud Run", readme)
        self.assertNotIn("terraform apply", operations.lower())

    def test_public_contact_ctas_use_canonical_contact_entrypoint(self):
        learning_slides = (
            ROOT / "addons/facodi-learning/facodi_learning/views/website_slides.xml"
        ).read_text()
        self.assertIn("/contact?course_id=%s", learning_slides)
        self.assertNotIn("/submissions/new?type=contact", learning_slides)

        snippet_root = ROOT / "addons/facodi-theme/theme_facodi/views/snippets"
        snippet_sources = "\n".join(
            path.read_text()
            for path in snippet_root.rglob("*.xml")
        )
        self.assertIn("/contact?source=", snippet_sources)
        self.assertNotIn("/submissions/new?type=contact", snippet_sources)

if __name__ == "__main__":
    unittest.main()
