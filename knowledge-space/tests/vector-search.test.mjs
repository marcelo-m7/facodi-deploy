import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {createHandler} from '../supabase/functions/knowledge-space-read/handler.mjs';

test('semantic RPC preserves row-level security and bounds output',()=>{
  const files=readdirSync(new URL('../supabase/migrations/',import.meta.url));
  const migration=files.find(f=>f.endsWith('_semantic_search.sql'));
  assert.ok(migration,'Semantic search migration exists');
  const sql=readFileSync(new URL(`../supabase/migrations/${migration}`,import.meta.url),'utf8');
  assert.match(sql,/security invoker/i);
  assert.match(sql,/status = 'approved'/i);
  assert.match(sql,/least\(.*12\)/i);
  assert.match(sql,/create policy .*ks_embeddings/i);
  assert.match(sql,/operator\(extensions\.<=>\)/i);
});

test('semantic search embeds user query and invokes vector RPC',async()=>{
  const calls=[];
  const handler=createHandler({url:'https://example.supabase.co',anonKey:'public-test'},async(url,options)=>{
    calls.push({url,options});
    return new Response('[{"id":"a","similarity":0.9}]',{status:200});
  },async query=>{assert.equal(query,'taxa de mudança');return Array(384).fill(.01);});
  const response=await handler(new Request('https://site.test/knowledge-space-read/semantic-search?q=taxa%20de%20mudan%C3%A7a'));
  assert.equal(response.status,200);
  assert.match(calls[0].url,/rpc\/ks_semantic_search/);
  assert.equal(JSON.parse(calls[0].options.body).query_embedding.length,384);
});

test('semantic search refuses malformed and oversized input',async()=>{
  const handler=createHandler({url:'https://example.supabase.co',anonKey:'public-test'},()=>{throw Error('network called');},()=>{throw Error('embedding called');});
  const response=await handler(new Request('https://site.test/semantic-search?q='+'a'.repeat(121)));
  assert.equal(response.status,400);
});
