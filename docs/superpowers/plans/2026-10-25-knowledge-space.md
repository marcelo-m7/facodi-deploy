# FACODI Knowledge Space V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a functional isolated knowledge-ontology pilot for Mathematics / Pre-Calculus using Supabase and a React explorer.

**Architecture:** Supabase hosts typed ontology relations, reviewed coverage and vector retrieval. Edge Functions expose bounded read APIs and privileged ingestion proposals. A standalone React/Vite app in the `facodi-deploy` experimental branch renders a chromatic wheel and graph without changing Odoo runtime.

**Tech Stack:** PostgreSQL, Supabase Edge Functions (Deno/TypeScript), pgvector, React, TypeScript, Vite, SVG/D3.

**Spec:** `docs/superpowers/specs/2026-10-25-knowledge-space-design.md`

## Global Constraints

- Work on `feature/knowledge-space-pilot` only; do not merge to `main` or activate Coolify.
- Respect `AGENTS.md`: Odoo owns approved curricula and editorial publication; do not duplicate course or progress models.
- Use project `bhfywztfyidvrlarebmg`; inspect existing schema and security advisors before change.
- Enable and test RLS on all exposed ontology tables; expose only approved records publicly.
- Keep real secrets out of repository, tests, logs and frontend bundles.
- Document illustrative sample mappings as unverified demonstrations.

## Review Focus

- Anonymous caller requests an unreviewed entity: API omits it entirely (Task 1 and 2 tests).
- Ingestion retries identical source revision: no new entities/relations (Task 3 test).
- Similar text but different curricular semantics: search response does not claim equivalence (Task 2 test).
- Cycle of proposed prerequisites: proposal rejected or flagged for review (Task 1 test).
- Wheel projects a four-dimensional knowledge mix into colour: original weights remain inspectable and unchanged (Task 4 test).

---

### Task 1: Ontology schema and security

**Files:**
- Create: `knowledge-space/supabase/migrations/<generated>_knowledge_space.sql`
- Create: `knowledge-space/tests/schema.test.ts`

**Interfaces:** Produces `ks_entities`, `ks_relations`, `ks_coverage`, `ks_embeddings`, `ks_ingestion_runs` with stable UUID IDs, constrained relation types, evidence/provenance and approval flags.

- [ ] Write failing schema/RLS tests for valid entities, approved-only reads, no self-edges, duplicate/cyclic prerequisites and coverage weights outside [0,1].
- [ ] Run the tests and confirm they fail against the absent schema.
- [ ] Generate migration using the Supabase CLI, implement tables, indexes, policies and grants. Preserve existing `facodi_processing_jobs`.
- [ ] Apply to controlled project context, run advisors and database assertions; verify all tests pass.
- [ ] Commit schema and its test evidence.

### Task 2: Public exploration API and vector search

**Files:**
- Create: `knowledge-space/supabase/functions/knowledge-space-read/index.ts`
- Create: `knowledge-space/supabase/functions/knowledge-space-read/handler.ts`
- Create: `knowledge-space/tests/read-api.test.ts`

**Interfaces:** `GET /entities`, `GET /entities/:id`, `GET /relations?entity_id=...`, `GET /search?q=...`; only approved records with bounded pagination and no sensitive audit data.

- [ ] Write failing API tests for filtering, paging, invalid IDs, malformed queries and semantic result provenance.
- [ ] Verify failure before implementation.
- [ ] Implement typed query/parsing/auth adapters and `pgvector` candidate retrieval, with empty/fallback behavior before embeddings exist.
- [ ] Run tests and confirm reviewed-only results; commit.

### Task 3: Idempotent curated pilot and proposed ingestion

**Files:**
- Create: `knowledge-space/supabase/seed/precalculus-demo.sql`
- Create: `knowledge-space/supabase/functions/knowledge-space-ingest/index.ts`
- Create: `knowledge-space/tests/ingestion.test.ts`

**Interfaces:** Ingestion accepts a versioned source URI + content hash, stores a proposed entity/relation set with evidence, returns job ID and never approves records.

- [ ] Write failing tests for duplicate replay, modified revision, failed extraction and unprivileged access.
- [ ] Verify failure; implement input validation and idempotent proposal persistence.
- [ ] Seed a modest source-labeled concept set, with interdisciplinary links but no official accreditation claim.
- [ ] Re-run tests and query actual persisted state; commit.

### Task 4: Independent interactive React explorer

**Files:**
- Create: `knowledge-space/web/package.json`
- Create: `knowledge-space/web/src/lib/knowledge.ts`
- Create: `knowledge-space/web/src/components/KnowledgeWheel.tsx`
- Create: `knowledge-space/web/src/components/KnowledgeGraph.tsx`
- Create: `knowledge-space/web/src/components/ConceptDetail.tsx`
- Create: `knowledge-space/web/src/App.tsx`
- Create: `knowledge-space/web/src/**/*.test.ts(x)`

**Interfaces:** UI consumes the read API, supports wheel/graph modes, selection, accessible keyboard navigation, search and inspectable 4D domain weights.

- [ ] Write failing projection tests (sum/normalization, 4D weights preserved), graph selection tests and keyboard tests.
- [ ] Verify failure; implement minimal Vite app, responsive UI and error/loading/empty states.
- [ ] Run unit tests, TypeScript checks and production build; visually inspect desktop and mobile.
- [ ] Commit frontend with independent setup instructions.

### Task 5: End-to-end verification and integration handoff

**Files:**
- Create: `knowledge-space/README.md`
- Create: `knowledge-space/tests/acceptance.md`
- Modify: `ARCHITECTURE.md` (short experimental-boundary note only)

**Interfaces:** Reproducible local start, backend configuration, demo reset, acceptance checks and explicit future Odoo hand-off contract.

- [ ] Test anonymous exploration against deployed read endpoint and test privileged-ingestion rejection for anonymous users.
- [ ] Run frontend production build and repository safety checks; record actual results and untested limitations.
- [ ] Confirm `main` remains unchanged, no Coolify deploy was triggered, and no Odoo editorial data was modified.
- [ ] Commit documentation and push feature branch; open draft PR without merge.
