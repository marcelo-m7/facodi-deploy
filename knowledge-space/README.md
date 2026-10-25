# FACODI Knowledge Space — experimental pilot

An independent React explorer over a Supabase ontology. Mathematics / Pre-Calculus is the demonstrator, not a certified curricular mapping. Nothing in this directory is part of FACODI's Odoo image, migration gate or Coolify production compose.

## Running locally

```bash
cd knowledge-space/web
npm ci
npm run dev
```

Open `http://127.0.0.1:5173`. The frontend points by default to the live **read-only** experimental API at `https://bhfywztfyidvrlarebmg.supabase.co/functions/v1/knowledge-space-read`; override `VITE_KS_API_URL` in a local `.env` if needed. No service-role credential belongs in the browser.

The frontend has an accessible chromatic wheel, a concept relationship graph, keyword filtering and a concept inspector. Colours are lossy projections of four-dimensional, nonnegative domain weight vectors. They do **not** measure certified competency or curricular equivalence.

## Supabase

Project: `bhfywztfyidvrlarebmg` (`facodi`). Applied migration: `supabase/migrations/20261025192850_knowledge_space.sql` (executed on 2026-10-25). The five `ks_` tables are isolated from the existing processing job table. Every new table has RLS enabled.

Read function: `knowledge-space-read` — public, read-only; PostgREST uses the anon key and its RLS policies. Endpoints: `GET /entities`, `GET /entities/:id`, `GET /relations?entity_id=<uuid>`, `GET /search?q=term`. The search endpoint is **lexical** for now; embeddings are provisioned but not generated.

Ingest function: `knowledge-space-ingest` — `verify_jwt=true` and strict service-role bearer-key comparison. Accepts a versioned, already-extracted structured payload (`source_uri`, hexadecimal `content_hash`, `entities[]`). It creates only **proposed** concepts and a durable idempotent job. It does not run transcription, AI enrichment, relation extraction or automatic approval. Never invoke it from the browser.

Demo seed: `supabase/seed/precalculus-demo.sql` inserted 11 approved, explicitly illustrative entities and 10 edges. They use `demo://precalculus` as provenance and cannot be presented as official ENEM / UAlg mappings.

### Planned next layer

- Extract transcripts/markdown using the existing FACODI processing boundary, propose concept and objective relations with cited evidence, then route to an Odoo Manager for review.
- Populate model-versioned 384-dimensional embeddings; compare pgvector retrieval with an optional standalone Python/FAISS benchmark using the same evaluation dataset. FAISS is **not** deployed inside Edge Functions.
- Formalize cross-curriculum coverage and reviewed publication handoff to Odoo. Existing `slide.channel`, `slide.slide` and FACODI curriculum review models remain canonical.

## Verification

```bash
cd knowledge-space/web
npm run test
npm run build
```

Also perform an anonymous GET of `/entities`; an anonymous POST to `/knowledge-space-ingest` must return HTTP 401. Validate mobile and desktop interactions in a browser before production use. This is a standalone experimental UI, not a production-ready FACODI module.
