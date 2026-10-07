#!/usr/bin/env python3
import http.client as http_client
"""Exercise the API through an isolated Odoo 19 HTTP and ORM runtime."""

import concurrent.futures
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit
from datetime import datetime, timedelta
from http.cookiejar import CookieJar


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.environ["FACODI_E2E_PROJECT"]
DATABASE = os.environ["FACODI_E2E_DATABASE"]
DB_USER = os.environ["FACODI_E2E_DB_USER"]
DB_PASSWORD = os.environ["FACODI_E2E_DB_PASSWORD"]
COMPOSE = [
    "docker", "compose", "--project-name", PROJECT, "--project-directory", ROOT,
    "--env-file", "/dev/null", "-f", "tests/docker-compose.api-e2e.yml",
]
odoo_container = subprocess.run(
    COMPOSE + ["ps", "-q", "odoo"],
    text=True,
    capture_output=True,
    check=True,
).stdout.strip()
published = subprocess.run(
    [
        "docker", "inspect", "--format",
        '{{range (index .NetworkSettings.Ports "8069/tcp")}}{{.HostIp}}:{{.HostPort}}{{end}}',
        odoo_container,
    ],
    text=True,
    capture_output=True,
    check=True,
).stdout.strip()
if not published.startswith("127.0.0.1:"):
    raise RuntimeError(f"Odoo port is not bound to loopback: {published!r}")
BASE_URL = "http://" + published


def odoo_shell(source):
    result = subprocess.run(
        COMPOSE + [
            "exec", "-T", "odoo", "odoo", "shell", "--no-http", "--log-level=critical",
            "--db_host=db", f"--db_user={DB_USER}", f"--db_password={DB_PASSWORD}",
            f"--database={DATABASE}",
        ],
        input=source,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError("Odoo shell assertion failed:\n" + result.stderr[-6000:])
    return result.stdout


def http(method, path, token=None, body=None, idempotency_key=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    if idempotency_key:
        headers["Idempotency-Key"] = idempotency_key
    request = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            content_type = response.headers.get("Content-Type", "")
            raw = response.read()
            result = json.loads(raw) if "json" in content_type else raw.decode("utf-8", "replace")
            return response.status, result
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            result = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            result = raw.decode("utf-8", "replace")
        return error.code, result


def content(channel_id, *, title="API E2E material", raw_content="First paragraph.\nSecond paragraph."):
    return {
        "source_type": "manual",
        "title": title,
        "raw_content": raw_content,
        "language": "en",
        "channel_id": channel_id,
    }


def fixture():
    marker = "FACODI_E2E_FIXTURE="
    source = f'''\
from datetime import datetime, timedelta
import json
import secrets
from odoo.fields import Command

operator_group = env.ref("facodi_api.group_pipeline_operator")
reviewer_group = env.ref("facodi_api.group_pipeline_reviewer")
reviewer_password = secrets.token_urlsafe(18)
operator = env["res.users"].create({{
    "name": "Disposable API Operator", "login": "api-operator-e2e",
    "email": "api-operator-e2e@example.invalid", "group_ids": [Command.set([operator_group.id])],
}})
reviewer = env["res.users"].create({{
    "name": "Disposable API Reviewer", "login": "api-reviewer-e2e",
    "email": "api-reviewer-e2e@example.invalid", "password": reviewer_password,
    "group_ids": [Command.set([reviewer_group.id])],
}})
observer = env["res.users"].create({{
    "name": "Disposable API Observer", "login": "api-observer-e2e",
    "email": "api-observer-e2e@example.invalid", "group_ids": [Command.set([operator_group.id])],
}})
channel = env["slide.channel"].create({{
    "name": "Disposable API E2E Course", "user_id": operator.id,
    "visibility": "public", "website_published": True,
}})
params = env["ir.config_parameter"].sudo()
params.set_param("facodi_api.pipeline_enabled", "true")
env.ref("facodi_api.ir_cron_facodi_pipeline_process").active = True
expiration = datetime.now() + timedelta(hours=1)
keys = {{
    "operator": env["res.users.apikeys"].with_user(operator).sudo()._generate("rpc", "e2e operator", expiration),
    "reviewer": env["res.users.apikeys"].with_user(reviewer).sudo()._generate("rpc", "e2e reviewer", expiration),
    "observer": env["res.users.apikeys"].with_user(observer).sudo()._generate("rpc", "e2e observer", expiration),
}}
env.cr.commit()
print("{marker}" + json.dumps({{"keys": keys, "channel_id": channel.id, "reviewer_password": reviewer_password}}))
'''
    output = fixture_output = odoo_shell(source)
    for line in fixture_output.splitlines():
        if line.startswith(marker):
            return json.loads(line[len(marker):])
    raise RuntimeError("Disposable fixture keys were not returned by Odoo shell")


def assert_run_private_before_processing(run_id):
    odoo_shell(f'''\
run = env["facodi.pipeline.run"].sudo().search([("run_id", "=", {run_id!r})], limit=1)
assert run.status == "received", run.status
assert run.project_id and run.task_id
assert run.project_id.privacy_visibility == "followers"
assert run.task_id.project_id == run.project_id
assert run.owner_id in run.task_id.user_ids
assert not run.published_slide_id
subtasks = env["project.task"].sudo().search([("parent_id", "=", run.task_id.id)], order="sequence")
assert len(subtasks) == 3, len(subtasks)
assert [s.sequence for s in subtasks] == [1, 2, 3]
print("PASS private Project and assigned Task exist before processing")
''')


def run_worker(run_id):
    odoo_shell(f'''\
cron = env.ref("facodi_api.ir_cron_facodi_pipeline_process")
assert cron.active
outcome = cron.method_direct_trigger()
assert outcome is True, outcome
print("PASS real ir.cron trigger completed")
''')
    odoo_shell(f'''\
run = env["facodi.pipeline.run"].sudo().search([("run_id", "=", {run_id!r})], limit=1)
assert run.status == "waiting_review", run.status
assert run.project_id.privacy_visibility == "followers"
assert run.metadata_json and run.artifacts_json
assert not run.published_slide_id
print("PASS actual ir.cron processed run into review without publication")
''')


def published_slide(run_id, expected_id=None):
    marker = "FACODI_E2E_SLIDE="
    output = odoo_shell(f'''\
import json
run = env["facodi.pipeline.run"].sudo().search([("run_id", "=", {run_id!r})], limit=1)
slide = run.published_slide_id
assert run.status == "published"
assert slide and slide.channel_id == run.target_channel_id
assert slide.is_published and slide.website_published
assert "<script>" not in (slide.html_content or "")
assert "&lt;script&gt;" in (slide.html_content or "")
print("{marker}" + json.dumps({{"id": slide.id, "url": slide.website_absolute_url}}))
''')
    for line in output.splitlines():
        if line.startswith(marker):
            result = json.loads(line[len(marker):])
            if expected_id is not None and result["id"] != expected_id:
                raise AssertionError("Approval replay created a duplicate slide")
            return result
    raise RuntimeError("Canonical published slide was not returned")


def wait_http():
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(BASE_URL + "/web/login", timeout=2):
                return
        except (OSError, urllib.error.URLError):
            time.sleep(0.5)
    raise RuntimeError("Odoo did not return after restart")


def reviewer_session(password):
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
    body = json.dumps({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {"db": DATABASE, "login": "api-reviewer-e2e", "password": password},
        "id": 1,
    }).encode()
    request = urllib.request.Request(
        BASE_URL + "/web/session/authenticate",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with opener.open(request, timeout=20) as response:
        result = json.loads(response.read()).get("result", {})
    if not result.get("uid"):
        raise RuntimeError("Disposable reviewer could not authenticate to the website")
    return opener


def main():
    wait_http()
    print(f"PASS host can reach isolated Odoo at {BASE_URL}")
    data = fixture()
    keys = data["keys"]
    channel_id = data["channel_id"]
    operator_key, reviewer_key, observer_key = keys["operator"], keys["reviewer"], keys["observer"]

    unauthorized_status, _ = http("POST", "/facodi/api/v2/pipeline/runs", body=content(channel_id), idempotency_key="no-key")
    assert unauthorized_status == 401, unauthorized_status

    # Verify bounded reading and 413 handling with and without Content-Length
    status_oversize_cl, _ = http("POST", "/facodi/api/v2/pipeline/runs", operator_key, content(channel_id, raw_content="A" * 300000), "oversize-cl")
    assert status_oversize_cl == 413, status_oversize_cl

    host, port_str = published.split(":")
    conn = http_client.HTTPConnection(host, int(port_str), timeout=15)
    conn.putrequest("POST", "/facodi/api/v2/pipeline/runs")
    conn.putheader("Authorization", f"Bearer {operator_key}")
    conn.putheader("Content-Type", "application/json")
    conn.putheader("Transfer-Encoding", "chunked")
    conn.putheader("Idempotency-Key", "oversize-chunked")
    conn.endheaders()
    chunk = b'{"raw_content": "' + b'B' * 300000 + b'"}'
    conn.send(bytes(hex(len(chunk))[2:], "ascii") + bytes([13, 10]) + chunk + bytes([13, 10, 48, 13, 10, 13, 10]))
    resp_chunked = conn.getresponse()
    assert resp_chunked.status == 413, resp_chunked.status
    conn.close()
    print("PASS bounded body reading enforces HTTP 413 with and without Content-Length")

    source = content(channel_id, raw_content="Safe <script>alert(1)</script> material.")
    status, accepted = http("POST", "/facodi/api/v2/pipeline/runs", operator_key, source, "review-run-1")
    assert status == 202 and accepted["status"] == "received", (status, accepted)
    run_id = accepted["run_id"]
    status, initial = http("GET", f"/facodi/api/v2/pipeline/runs/{run_id}", operator_key)
    assert status == 200 and initial["status"] == "received", (status, initial)
    assert_run_private_before_processing(run_id)
    print("PASS bearer HTTP submission returned 202 without synchronous processing")

    status, conflict = http(
        "POST", "/facodi/api/v2/pipeline/runs", operator_key,
        content(channel_id, title="Changed payload"), "review-run-1",
    )
    assert status == 409 and conflict.get("error") == "idempotency_conflict", (status, conflict)
    concurrent_payload = content(channel_id, title="Concurrent retry")
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        responses = list(executor.map(
            lambda _: http("POST", "/facodi/api/v2/pipeline/runs", operator_key, concurrent_payload, "race-key-1"),
            range(6),
        ))
    assert all(status in (200, 202) for status, _ in responses), responses
    assert len({value["run_id"] for _, value in responses}) == 1, responses
    print("PASS divergent payload conflict and concurrent retry idempotency")

    observer_status, _ = http("GET", f"/facodi/api/v2/pipeline/runs/{run_id}", observer_key)
    reviewer_as_operator_status, _ = http("POST", f"/facodi/api/v2/pipeline/runs/{run_id}/approve", operator_key, {})
    assert observer_status == 404, observer_status
    assert reviewer_as_operator_status == 403, reviewer_as_operator_status
    print("PASS run owner visibility and operator/reviewer role separation")

    run_worker(run_id)
    status, pending = http("GET", f"/facodi/api/v2/pipeline/runs/{run_id}", operator_key)
    assert status == 200 and pending["status"] == "waiting_review"
    assert pending["artifacts"]["enriched"]
    print("PASS worker creates review artifacts while canonical content is unpublished")

    status, approved = http("POST", f"/facodi/api/v2/pipeline/runs/{run_id}/approve", reviewer_key, {})
    assert status == 200 and approved["status"] == "published", (status, approved)
    slide = published_slide(run_id, approved["slide_id"])
    status, replay = http("POST", f"/facodi/api/v2/pipeline/runs/{run_id}/approve", reviewer_key, {})
    assert status == 200 and replay["slide_id"] == slide["id"], (status, replay)
    lesson_path = urlsplit(slide["url"]).path
    if urlsplit(slide["url"]).query:
        lesson_path += "?" + urlsplit(slide["url"]).query
    website = reviewer_session(data["reviewer_password"])
    with website.open(BASE_URL + lesson_path, timeout=20) as response:
        page_status = response.status
        page = response.read().decode("utf-8", "replace")
    assert page_status == 200 and "API E2E material" in page and "Safe" in page, (page_status, page[:300])
    print("PASS reviewer approval publishes canonical slide once and website serves it")

    subprocess.run(COMPOSE + ["restart", "odoo"], check=True, capture_output=True, text=True)
    wait_http()
    status, restarted = http("GET", f"/facodi/api/v2/pipeline/runs/{run_id}", operator_key)
    assert status == 200 and restarted["status"] == "published", (status, restarted)
    published_slide(run_id, slide["id"])
    with website.open(BASE_URL + lesson_path, timeout=20) as response:
        assert response.status == 200 and "API E2E material" in response.read().decode("utf-8", "replace")
    print("PASS run and canonical publication survive Odoo restart")


if __name__ == "__main__":
    main()