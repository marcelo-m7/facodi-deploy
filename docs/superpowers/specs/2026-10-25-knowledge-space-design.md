# FACODI Knowledge Space V1 — Design

## Intent

Prototype an extensible, curriculum-independent knowledge ontology, using Mathematics / Pre-Calculus as the first domain, with an independent React explorer and Supabase-backed read API. The prototype must not modify FACODI's live Odoo editorial records or trigger Coolify production deployment.

## Goals

- Represent concepts, competencies, learning objectives, sources, curricula and typed directed relations with provenance and review status.
- Link existing learning resources to those entities without duplicating Odoo courses or learner progress.
- Support reproducible graph traversal, curriculum-content coverage matrices and vector-assisted discovery.
- Explore the same data through a chromatic knowledge wheel and a relationship graph.
- Keep data exploration public only for approved material; protect drafts, proposals and privileged ingestion.

## Non-goals

- Award credits, qualifications, academic equivalence or learner mastery.
- Automatically publish or mutate `slide.channel`, `slide.slide` or curricular coverage in Odoo.
- Replace the existing FACODI ingestion provider and editorial approval workflow.
- Merge the branch or deploy to production in V1.

## Existing architecture constraints

`facodi-deploy` owns runtime composition and pins. Business/editorial models belong to `facodi-learning` and presentation in `facodi-theme`. Supabase owns durable processing jobs; Odoo remains the editorial system of record. The active Supabase project is `bhfywztfyidvrlarebmg`, with existing `public.facodi_processing_jobs` and RLS. Use separate namespaced tables rather than changing that table. No production compose changes.

## Approaches

1. **Selected — isolated React/Vite app in a feature branch:** independent visual iteration and read API, without Odoo deployment changes; a later separately approved service deployment is needed.
2. Odoo Website page: direct integration, but couples experimental UI to migration/theme/release gates; defer.

Within Supabase, begin with `pgvector` for Postgres-native retrieval; measure FAISS with Python separately if search scale or performance justifies it. No FAISS server in the Edge Function runtime.

## Logical model

- `ks_entities`: stable entity identifiers, kind (`concept`, `competency`, `objective`, `curriculum`, `resource`), label, definition, domain, revision, review status and provenance.
- `ks_relations`: source/target entity IDs, controlled relation type (`prerequisite_of`, `part_of`, `applied_in`, `develops_competency`, `addresses_objective`, `references_resource`, `aligned_to`), evidence, review status; prevent self-links and deduplicate equivalent directed edges.
- `ks_embeddings`: vector representations with model identifier, version and content hash. Semantic similarity proposes candidates but never makes editorial assertions.
- `ks_coverage`: resource-to-objective evidence and weights in [0,1], reviewed independently from embeddings; no automatic equivalence claims.
- `ks_ingestion_runs`: idempotent source/revision processing audit and sanitized error data.

The conceptual matrix is content-by-learning-objective; entries mean reviewed coverage, not personal mastery. Domain weights are stored independently of RGB; wheel angle/colour is a lossy but explainable projection. Radius encodes a declared granularity level, not inferred academic difficulty. Cross-domain relationships are visible as graph links.

## Interfaces

- Read-only public Edge API returns bounded, reviewed-only entity summaries, edges, domain weights, source references and vector-search results.
- Privileged ingestion invokes an idempotent Edge endpoint, creates proposed facts with evidence and refuses to publish them automatically.
- React/TypeScript/Vite app exposes `Wheel`, `Graph`, `ConceptDetail` and `Search` surfaces; URL state preserves selected entity and view mode.

## Initial corpus and acceptance

Seed a small clearly marked demo ontology for limits, derivatives, functions and rates of change, with prerequisite and interdisciplinary relations. Never present illustrative links as officially certified ENEM or UAlg mappings. Acceptance covers isolated git branch, migration dry-run/reversible review, strict RLS, approved-only anonymous data, stable ingestion replay, graph/matrix invariants, responsive wheel and keyboard-accessible exploration. Run repository contracts where relevant and frontend tests/build. No merge or Coolify trigger.
