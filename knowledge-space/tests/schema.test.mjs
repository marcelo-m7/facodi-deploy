import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/migrations/20261025192850_knowledge_space.sql', import.meta.url), 'utf8');

test('schema separates five knowledge tables and constrains reviewed data', () => {
  for (const table of ['ks_entities', 'ks_relations', 'ks_coverage', 'ks_embeddings', 'ks_ingestion_runs']) {
    assert.match(sql, new RegExp(`create table if not exists public\\.${table}`, 'i'));
    assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
  }
  assert.match(sql, /check \(weight >= 0 and weight <= 1\)/i);
  assert.match(sql, /check \(source_id <> target_id\)/i);
  assert.match(sql, /status = 'approved'/i);
  assert.match(sql, /revoke all on .*ks_ingestion_runs/i);
});
