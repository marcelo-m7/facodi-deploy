# Monynha MCP FACODI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an isolated Open2 OAuth consent UI on facodi.com and a gated MCP Coolify deployment candidate.

**Architecture:** `facodi_mcp_oauth` is a stand-alone Odoo Website addon in the FACODI API repository with a public, fail-closed QWeb route and locally bundled Supabase client code. The FACODI deploy repo pins the addon owner SHA and an immutable MCP source SHA; the MCP remains an opt-in Compose profile backed by isolated Postgres.

**Tech Stack:** Odoo 19 Community Python/QWeb, JavaScript + pinned `@supabase/supabase-js`, node test, Docker Compose/Coolify, PostgreSQL 17, Monynha FastMCP Python 3.12.

**Spec:** `docs/superpowers/specs/2026-10-28-monynha-mcp-facodi-integration-design.md`.

## Global Constraints

- Open2 project ID is `wvkjainfwsyiyfcmbtid`, consent path `/oauth/consent`, no new Supabase project or global redirect change.
- Default deny when publishable key or approved OAuth client IDs are absent.
- Never publish database ports, transfer `service_role` to browser/MCP, or modify existing FACODI persistent volume names.
- Do not merge into `facodi-deploy/main` before explicit production acceptance; that branch triggers Coolify rebuild.

## Review Focus

- `authorization_id` absent/invalid → fail closed without redirect.
- Unknown client ID → no approve/deny action sent to Supabase.
- Unauthenticated Open2 user → login form only; unrelated Odoo session does not grant consent.
- Supabase SDK errors or malformed redirect → stay on consent page with safe error.
- MCP profile not enabled → existing FACODI Odoo runtime unchanged.

---

### Task 1: FACODI OAuth consent addon

**Files:** `facodi-api/facodi_mcp_oauth/{__manifest__.py,__init__.py,controllers/consent.py,views/consent.xml,static/src/js/*,static/src/css/*}`, `facodi-api/tests/test_mcp_oauth_contract.py`.

**Interfaces:** `/oauth/consent` renders an HTML page embedding only Open2 project URL and publishable key; JS invokes `supabase.auth.oauth.getAuthorizationDetails`, `approveAuthorization`, `denyAuthorization`; server verifies approved client allowlist configuration.

- [ ] Write focused failing Python contract and browser-logic Node tests for route/manifest, missing configuration, invalid ID, unknown client, sign-in, approve and deny.
- [ ] Run them and confirm the expected missing-feature failures.
- [ ] Implement Odoo controller, native QWeb markup, accessible stylesheet and pinned bundled client.
- [ ] Re-run tests, then existing API tests; inspect Odoo 19 compatibility.
- [ ] Commit in the owner repo and publish a review PR.

### Task 2: Isolated MCP Coolify profile

**Files:** `facodi-deploy/deploy/coolify/docker-compose.yml`, `docker/entrypoint.sh`, `tests/test_monynha_deployment_contract.py`, existing exact module list contracts, `.env.example`, `docs/operations.md`.

**Interfaces:** Compose opt-in services `monynha-db`, `monynha-mcp`, with private DB, readiness and no published ports, immutable MCP build source and strict environment requirements.

- [ ] Write and fail regression tests for compose isolation, inactive default profile and exact domain/secret gates.
- [ ] Implement the profile, frontend module installation and documentation with preserved existing names.
- [ ] Validate Compose syntax and existing runtime tests where Docker is available; review backups and rollback.
- [ ] Publish draft deployment PR pinning a reviewed `facodi-api` commit; keep unmerged.

### Task 3: Live acceptance (separate rollout gate)

- [ ] Confirm approved MCP public HTTPS URL and DNS/Coolify proxy configuration.
- [ ] Obtain signed real Open2 OAuth grant tokens and verify audience binding and ordinary-session regressions.
- [ ] Review/enable a least-privilege Open2 audience hook only after impact analysis and approval.
- [ ] Restore-test independent MCP database backup, read-only Odoo connection policies and blocked writes.
- [ ] Take paired FACODI Postgres/filestore backups, review PRs and authorize production merge/deploy.
