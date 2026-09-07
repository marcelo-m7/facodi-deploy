from __future__ import annotations

from playwright.sync_api import Page, expect

BASE_URL = "http://127.0.0.1:8069"


def login(page: Page) -> None:
    page.goto(f"{BASE_URL}/web/login", wait_until="domcontentloaded")
    page.locator("input[name='login']").fill("admin")
    page.locator("input[name='password']").fill("facodi-ci-admin")
    page.locator("button[type='submit']").click()
    page.locator(".o_web_client").wait_for(state="attached", timeout=30_000)


def test_facodi_runtime_loads_monodoo_home_theme_and_appsbar(page: Page) -> None:
    login(page)
    page.goto(f"{BASE_URL}/odoo", wait_until="domcontentloaded")

    expect(page.locator(".o_monodoo_home")).to_be_visible(timeout=30_000)
    expect(page.locator(".o_monodoo_appsbar")).to_be_visible(timeout=30_000)

    theme = page.evaluate(
        """() => ({
            mode: document.documentElement.dataset.monodooTheme,
            key: document.documentElement.dataset.monodooThemeKey,
            primary: getComputedStyle(document.documentElement)
                .getPropertyValue('--monodoo-primary')
                .trim(),
        })"""
    )
    assert theme["mode"] in {"light", "dark"}
    assert theme["key"]
    assert theme["primary"]
