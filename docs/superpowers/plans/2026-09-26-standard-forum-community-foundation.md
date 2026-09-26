# FACODI Standard Forum Community Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Odoo 19's standard Forum and eLearning/Forum bridge explicit, migration-safe runtime capabilities of FACODI without introducing a parallel community model.

**Architecture:** `website_forum` remains authoritative for forums, posts, tags, karma, ranks, badges and moderation. `website_slides_forum` provides the standard `slide.channel.forum_id` integration. This repository only composes, migrates, documents and acceptance-tests those standard modules.

**Tech Stack:** Odoo 19 Community, `website_forum`, `website_slides_forum`, Python migration gate, Docker Compose/Coolify, unittest/shell runtime contracts.

**Spec:** Approved Standard-first + fine FACODI integration, beginning with existing Odoo resources.

## Global Constraints
- Do not create parallel forum, post, karma, badge, rank, profile, course or progress models.
- Preserve standard Odoo Forum/eLearning controllers and `/forum`.
- Do not seed fictional discussions, users, karma, ranks or per-course forums.
- Existing databases install newly required modules through the generic fail-closed migration phase.
- Keep this repository limited to composition, migration, documentation and integration validation.

## Review Focus
- Missing standard forum modules on an existing database are initialized before canonical update.
- Already-installed standard modules are not reinitialized.
- Runtime module strings remain identical across entrypoint, Coolify and tests.
- `website_slides_forum` is explicit rather than replaced by custom linkage.
- Public acceptance proves `/forum` without fake content.

---

### Task 1: Pin standard community modules in the runtime contract
**Files:** `tests/test_repository_contract.py`, `tests/test_migration_contract.py`, `docker/entrypoint.sh`, `deploy/coolify/docker-compose.yml`.

- [ ] Write failing expectations for canonical `FACODI_MODULES` containing `website_forum,website_slides_forum`, including the existing-database missing-module initialization case.
- [ ] Run `python3 -m unittest tests.test_repository_contract tests.test_migration_contract -v`; expect failure before implementation.
- [ ] Append both standard modules consistently to entrypoint and both Coolify services.
- [ ] Run the same tests; expect PASS.

### Task 2: Prove native Forum/eLearning integration at runtime
**Files:** `tests/test_coolify_runtime.sh`.

- [ ] Require installed states for `website_forum` and `website_slides_forum`.
- [ ] Verify standard `forum.forum`, `forum.post` and `slide.channel.forum_id` exist in the disposable Odoo registry.
- [ ] Preserve the public `/forum` HTTP acceptance.
- [ ] Do not create forum posts, users, karma, badges or course forums for the test.
- [ ] Run `bash scripts/validate-repository.sh`; full disposable Docker acceptance remains a CI gate.

### Task 3: Document the standard-first community boundary
**Files:** `ARCHITECTURE.md`, `docs/operations.md`.

- [ ] Document Forum ownership and the standard `website_slides_forum` course linkage.
- [ ] Add standard community module/route checks to consequential deployment acceptance.
- [ ] Run `bash scripts/validate-repository.sh`; expect PASS.
