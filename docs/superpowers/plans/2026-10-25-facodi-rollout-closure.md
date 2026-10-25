# FACODI Rollout Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 22 October 2026 translation-editor and Learning rollout gaps without overwriting live editorial views or unnecessarily changing the production image.

**Architecture:** The theme repository owns the editor-generated homepage snapshot and its recovery tooling. The deployment repository owns authoritative source pins and operational acceptance instructions. An archived snapshot is never automatically imported; a portable replay candidate is generated only for a verified parent view and remains subject to manual review.

**Tech Stack:** Odoo 19 Community, QWeb/XML, Python unittest, lxml available in the Odoo 19 CI image, GitHub Actions, Coolify Compose.

**Spec:** `docs/translation-editor-2026-10-22.md`, plus the 25 October rollout audit and production view comparisons.

## Global Constraints

- Keep `theme_facodi` at `19.0.10.91.0` and `facodi_learning` at `19.0.2.3.2` unless a real addon runtime change is necessary.
- Preserve the production editor-owned view `#6762` and its exact source snapshot; never autoimport from a theme manifest.
- Do not modify or recreate Coolify `postgres-data` or `odoo-data` volumes.
- Do not claim a completed rollout from successful CI or public HTTP responses alone.

## Review Focus

- Archived selector matches a live `<section>` but current source uses `<div>`: generate a compatible candidate without mutating the archive.
- Missing or duplicate dynamic content target: fail closed without creating a candidate.
- The new contract must run in normal CI, not only in an opt-in workflow.
- Source pins documented as current must agree with the gitlinks and explicitly distinguish history.
- CI rerun and public UI checks must not be misrepresented as authenticated editor QA or a verified Coolify image SHA.

---

### Task 1: Theme recovery contract

**Files:**
- Create `facodi-theme/scripts/prepare_home_curated_snapshot.py`.
- Modify `facodi-theme/tests/test_editorial_home_curated_snapshot.py`.
- Modify `facodi-theme/.github/workflows/ci.yml`.
- Modify `facodi-theme/theme_facodi/data/website_snapshots/README.md`.

**Interfaces:** CLI `--parent PATH --output PATH` produces a manually reviewable rebased XML file when exactly one target with CSS class `s_dynamic_snippet_content` exists, otherwise exits nonzero; no Odoo writes.

- [ ] Write tests for the current `<div>` source, original archive preservation, missing target, and multiple targets.
- [ ] Run the tests to demonstrate the current missing recovery capability.
- [ ] Implement the narrow read-only replay-preparation CLI.
- [ ] Run tests to green, and wire them into the standard theme CI using the Odoo 19 image.
- [ ] Update snapshot instructions to distinguish the persisted live `<section>` from the repository `<div>`.
- [ ] Run local static contracts, inspect the diff, and commit the theme branch.

### Task 2: Deploy pin documentation and operational gate

**Files:**
- Modify `facodi-deploy/ARCHITECTURE.md`.
- Modify `facodi-deploy/docs/translation-editor-2026-10-22.md`.
- Retain this plan as release audit documentation.

**Interfaces:** Source pins are copied from the git tree and labeled current; the runbook distinguishes ORM module versions, image SHA, one-shot migration logs, CI, and authenticated browser acceptance.

- [ ] Confirm current `main` gitlinks for API, AI, Learning, Theme and related modules.
- [ ] Update only stale pin inventory rows and clarify their authority.
- [ ] Add concrete acceptance criteria for the snapshot compatibility gate and post-deploy verification.
- [ ] Run repository/doc contracts and inspect the diff.
- [ ] Commit the deploy branch without changing gitlinks or runtime Compose.

### Task 3: Verify and promote safely

**Files:** No expected production source changes.

**Interfaces:** GitHub PRs and CI; read-only Odoo and browser verification; Coolify evidence where available.

- [ ] Inspect the isolated runtime CI rerun and report the exact outcome.
- [ ] Create theme and deploy PRs after their local checks; verify remote CI.
- [ ] Do not merge or push to the deployment branch watched by Coolify until integration impact is assessed.
- [ ] Compare installed module versions and public pages after any deployment event.
- [ ] Keep authenticated editor and recovery testing explicitly open if credentials or Coolify evidence are unavailable.
