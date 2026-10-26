# Pilot acceptance — 2026-10-25

| Gate | Evidence | Result |
| --- | --- | --- |
| Isolated branch | `feature/knowledge-space-pilot` | Prepared locally |
| Supabase tables | `ks_entities`, `ks_relations`, `ks_coverage`, `ks_embeddings`, `ks_ingestion_runs`; all RLS | Verified through Supabase project inventory |
| Anonymous read | Public Edge Function `/entities` responded with 11 demonstrative entities | Verified |
| Anonymous relationships | Under `anon` role, query returned 10 reviewed edges | Verified |
| Ingestion protection | Anonymous POST returns HTTP 401 | Verified |
| Schema security advisors | No high-severity lints; two informational notices for private tables intentionally lacking read policies | Verified |
| Vector embedding population | Admin index worker available; no privileged indexing run executed yet | Pending |
| Semantic retrieval API | `gte-small` Edge inference and security-invoker pgvector RPC; anonymous query returned HTTP 200 and no hits on empty index | Verified API, index empty |
| Guarded index worker | `knowledge-space-index` deployed with JWT requirement; anonymous POST returned HTTP 401 | Verified access restriction; privileged batch not run |
| Automated enrichment | Existing FACODI pipeline not connected | Deferred |
| Frontend build / tests | `npm run test`: 7 suites, 0 failures; `npm run build`: generated production bundle | Verified locally |
| Real browser visual QA | Playwright Chromium download failed; cloud browser cannot reach local port (`ERR_CONNECTION_REFUSED`). Visual inspection still required | Blocked / pending |
| Coolify production | No deployment or main merge requested | Deliberately untouched |
