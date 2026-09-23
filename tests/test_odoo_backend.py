from __future__ import annotations

from playwright.sync_api import Page

BASE_URL = "http://127.0.0.1:8069"


def test_facodi_runtime_loads_standard_odoo_webclient(page: Page) -> None:
    page.goto(f"{BASE_URL}/web/login", wait_until="domcontentloaded")
    page.locator("input[name='login']").fill("admin")
    page.locator("input[name='password']").fill("facodi-ci-admin")
    page.get_by_role("button", name="Log in").click()
    page.locator(".o_web_client").wait_for(state="attached", timeout=30_000)
    page.goto(f"{BASE_URL}/odoo", wait_until="domcontentloaded")
    page.locator(".o_web_client").wait_for(state="attached", timeout=30_000)