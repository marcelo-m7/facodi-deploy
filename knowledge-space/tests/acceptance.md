# Pilot acceptance — 2026-10-25

| Gate | Evidence | Result |
| --- | --- | --- |
| Isolated branch | `feature/knowledge-space-pilot` | Prepared locally |
| Supabase tables | `ks_entities`, `ks_relations`, `ks_coverage`, `ks_embeddings`, `ks_ingestion_runs`; all RLS | Verified through Supabase project inventory |
| Anonymous read | Public Edge Function `/entities` responded with 11 demonstrative entities | Verified |
| Anonymous relationships | Under `anon` role, query returned 10 reviewed edges | Verified |
| Ingestion protection | Anonymous POST returns HTTP 401 | Verified |
| Schema security advisors | No high-severity lints; two informational notices for private tables intentionally lacking read policies | Verified |
| Vector embedding retrieval | No embedding generator or query vectors attached yet | Deferred |
| Automated enrichment | Existing FACODI pipeline not connected | Deferred |
| Frontend build / tests | `npm run test`: 4 test files, 0 failures; `npm run build`: Vite production bundle generated | Verified locally |
| Real browser visual QA | Still required before deployment | Pending |
| Coolify production | No deployment or main merge requested | Deliberately untouched |
