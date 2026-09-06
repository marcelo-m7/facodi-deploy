#!/usr/bin/env python3
"""Fail-closed FACODI migration orchestration for the Coolify runtime."""

from __future__ import annotations

import argparse
import re
import subprocess
import textwrap


def run(command: list[str], *, input_text: str | None = None) -> None:
    subprocess.run(command, input=input_text, text=True, check=True)


def psql_scalar(sql: str, *, database: str | None = None) -> str:
    command = ["psql", "-v", "ON_ERROR_STOP=1"]
    if database:
        command.extend(["--dbname", database])
    command.extend(["-Atqc", sql])
    result = subprocess.run(
        command,
        text=True,
        check=True,
        capture_output=True,
    )
    return result.stdout.strip()


def psql_script(sql: str) -> None:
    run(["psql", "-v", "ON_ERROR_STOP=1"], input_text=sql)


def database_exists(database: str) -> bool:
    databases = psql_scalar("SELECT datname FROM pg_database", database="postgres")
    return database in databases.splitlines()


def registry_exists(database: str) -> bool:
    if not database_exists(database):
        return False
    return (
        psql_scalar(
            "SELECT to_regclass('public.ir_module_module') IS NOT NULL",
            database=database,
        )
        == "t"
    )


def parse_modules(modules: str) -> list[str]:
    names = [name.strip() for name in modules.split(",") if name.strip()]
    if not names or any(not re.fullmatch(r"[A-Za-z0-9_]+", name) for name in names):
        raise RuntimeError("FACODI_MODULES contains an invalid Odoo module name")
    return names


def missing_modules(database: str, modules: str) -> str:
    """Return requested modules which are not installed in an existing registry."""
    names = parse_modules(modules)
    quoted = ", ".join(f"'{name}'" for name in names)
    installed = set(
        psql_scalar(
            "SELECT name FROM ir_module_module "
            "WHERE state='installed' "
            f"AND name IN ({quoted}) ORDER BY name",
            database=database,
        ).splitlines()
    )
    return ",".join(name for name in names if name not in installed)


def inspect_legacy_state() -> str:
    """Return absent/current/legacy, refusing every ambiguous legacy state."""
    old_state = psql_scalar(
        "SELECT state FROM ir_module_module WHERE name='website_facodi' LIMIT 1"
    )
    new_state = psql_scalar(
        "SELECT state FROM ir_module_module WHERE name='theme_facodi' LIMIT 1"
    )

    if not old_state:
        return "current" if new_state else "absent"
    if new_state:
        raise RuntimeError(
            "Both website_facodi and theme_facodi exist; refusing an ambiguous transition."
        )

    unexpected_xmlids = psql_scalar(
        """
        SELECT count(*)
          FROM ir_model_data
         WHERE module='website_facodi'
           AND NOT (model='ir.ui.view' AND name='website_layout')
        """
    )
    if unexpected_xmlids != "0":
        raise RuntimeError(
            "Legacy website_facodi owns unexpected XML IDs; refusing automatic transition."
        )

    legacy_view_id = psql_scalar(
        """
        SELECT res_id
          FROM ir_model_data
         WHERE module='website_facodi'
           AND model='ir.ui.view'
           AND name='website_layout'
         LIMIT 1
        """
    )
    if legacy_view_id:
        dependent_views = psql_scalar(
            f"""
            SELECT count(*)
              FROM ir_ui_view
             WHERE inherit_id={int(legacy_view_id)}
               AND id <> {int(legacy_view_id)}
            """
        )
        if dependent_views != "0":
            raise RuntimeError(
                "Legacy website_facodi view has dependent custom views; refusing automatic transition."
            )

    return "legacy"


def transition_legacy_theme() -> None:
    """Remove only the known presentation-only legacy module metadata."""
    psql_script(
        """
        BEGIN;

        DO $$
        DECLARE
            legacy_id integer;
            new_count integer;
            unexpected_count integer;
            dependent_count integer;
        BEGIN
            SELECT id INTO legacy_id
              FROM ir_module_module
             WHERE name = 'website_facodi'
             LIMIT 1;

            IF legacy_id IS NULL THEN
                RETURN;
            END IF;

            SELECT count(*) INTO new_count
              FROM ir_module_module
             WHERE name = 'theme_facodi';
            IF new_count <> 0 THEN
                RAISE EXCEPTION 'theme_facodi already exists; transition is ambiguous';
            END IF;

            SELECT count(*) INTO unexpected_count
              FROM ir_model_data
             WHERE module = 'website_facodi'
               AND NOT (model = 'ir.ui.view' AND name = 'website_layout');
            IF unexpected_count <> 0 THEN
                RAISE EXCEPTION 'website_facodi owns unexpected XML IDs';
            END IF;

            SELECT count(*) INTO dependent_count
              FROM ir_ui_view child
             WHERE child.inherit_id IN (
                 SELECT res_id
                   FROM ir_model_data
                  WHERE module = 'website_facodi'
                    AND model = 'ir.ui.view'
                    AND name = 'website_layout'
             );
            IF dependent_count <> 0 THEN
                RAISE EXCEPTION 'website_facodi layout has dependent custom views';
            END IF;
        END $$;

        DELETE FROM ir_ui_view
         WHERE id IN (
             SELECT res_id
               FROM ir_model_data
              WHERE module = 'website_facodi'
                AND model = 'ir.ui.view'
                AND name = 'website_layout'
         );

        DELETE FROM ir_model_data
         WHERE module = 'website_facodi';

        DELETE FROM ir_model_data
         WHERE module = 'base'
           AND model = 'ir.module.module'
           AND name = 'module_website_facodi'
           AND res_id IN (
               SELECT id FROM ir_module_module WHERE name = 'website_facodi'
           );

        DELETE FROM ir_module_module
         WHERE name = 'website_facodi';

        COMMIT;
        """
    )


def run_module_operation(
    config: str, database: str, modules: str, *, initialize: bool
) -> None:
    operation = f"--init=base,{modules}" if initialize else f"--update={modules}"
    run(
        [
            "odoo",
            "server",
            f"--config={config}",
            f"--database={database}",
            "--stop-after-init",
            "--without-demo=True",
            operation,
        ]
    )


def run_shell(config: str, database: str, payload: str) -> None:
    run(
        ["odoo", "shell", f"--config={config}", "-d", database],
        input_text=textwrap.dedent(payload),
    )


def configure_languages(config: str, database: str) -> None:
    run_shell(
        config,
        database,
        """
        Lang = env["res.lang"]
        lang_en = env.ref("base.lang_en")
        lang_pt = Lang._activate_lang("pt_PT")
        lang_es = Lang._activate_lang("es_ES")
        lang_fr = Lang._activate_lang("fr_FR")
        required = (lang_en, lang_pt, lang_es, lang_fr)
        if not all(required):
            raise RuntimeError("FACODI Website languages are not available")

        theme = env["ir.module.module"].search(
            [("name", "=", "theme_facodi"), ("state", "=", "installed")], limit=1
        )
        if not theme:
            raise RuntimeError("theme_facodi must be installed before translations are loaded")
        theme._update_translations(["pt_PT", "es_ES", "fr_FR"])

        websites = env["website"].search([])
        if not websites:
            raise RuntimeError("No Website record exists after FACODI module installation")
        for website in websites:
            website.language_ids = lang_en + lang_pt + lang_es + lang_fr
            website.default_lang_id = lang_en
        env.cr.commit()
        """,
    )


def apply_theme(config: str, database: str) -> None:
    run_shell(
        config,
        database,
        """
        theme = env["ir.module.module"].search(
            [("name", "=", "theme_facodi"), ("state", "=", "installed")], limit=1
        )
        if not theme:
            raise RuntimeError("theme_facodi must be installed before applying it")
        websites = env["website"].search([])
        if not websites:
            raise RuntimeError("No Website record exists after FACODI module installation")
        for website in websites:
            theme.with_context(website_id=website.id).button_choose_theme()
        env.cr.commit()
        """,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--database", required=True)
    parser.add_argument("--modules", required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    initialize = not registry_exists(args.database)
    if initialize:
        run_module_operation(
            args.config,
            args.database,
            args.modules,
            initialize=True,
        )
    else:
        state = inspect_legacy_state()
        if state == "legacy":
            transition_legacy_theme()

        to_install = missing_modules(args.database, args.modules)
        if to_install:
            run_module_operation(
                args.config,
                args.database,
                to_install,
                initialize=True,
            )
        run_module_operation(
            args.config,
            args.database,
            args.modules,
            initialize=False,
        )

    configure_languages(args.config, args.database)
    apply_theme(args.config, args.database)


if __name__ == "__main__":
    main()
