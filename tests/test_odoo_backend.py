from __future__ import annotations

import os

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


def _jsonrpc(page: Page, route: str, params: dict[str, object]) -> dict[str, object]:
    response = page.evaluate(
        """async ({ route, params }) => {
            const response = await fetch(route, {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({jsonrpc: "2.0", method: "call", params, id: 1}),
            });
            return response.json();
        }""",
        {"route": route, "params": params},
    )
    assert "error" not in response, response
    return response["result"]


def test_learner_can_enroll_complete_video_and_pass_quiz(page: Page) -> None:
    course_route = os.environ["FACODI_RUNTIME_COURSE_ROUTE"]
    course_id = int(os.environ["FACODI_RUNTIME_COURSE_ID"])
    video_id = int(os.environ["FACODI_RUNTIME_VIDEO_ID"])
    quiz_id = int(os.environ["FACODI_RUNTIME_QUIZ_ID"])
    answer_id = int(os.environ["FACODI_RUNTIME_QUIZ_ANSWER_ID"])

    page.goto(f"{BASE_URL}/web/login", wait_until="domcontentloaded")
    page.locator("input[name='login']").fill("facodi-ci-learner")
    page.locator("input[name='password']").fill("facodi-ci-learner")
    page.get_by_role("button", name="Log in").click()
    page.wait_for_url(f"{BASE_URL}/web", timeout=30_000)

    page.goto(f"{BASE_URL}{course_route}", wait_until="domcontentloaded")
    join = page.locator(".o_wslides_js_course_join_link")
    join.click()
    join.wait_for(state="detached", timeout=30_000)

    page.goto(f"{BASE_URL}/slides/slide/{video_id}", wait_until="domcontentloaded")
    video_progress = _jsonrpc(page, "/slides/slide/set_completed", {"slide_id": video_id})
    assert float(video_progress["channel_completion"]) > 0

    page.goto(f"{BASE_URL}/slides/slide/{quiz_id}", wait_until="domcontentloaded")
    quiz_progress = _jsonrpc(
        page,
        "/slides/slide/quiz/submit",
        {"slide_id": quiz_id, "answer_ids": [answer_id]},
    )
    assert quiz_progress["completed"] is True
    assert float(quiz_progress["channel_completion"]) == 100
    assert course_id > 0