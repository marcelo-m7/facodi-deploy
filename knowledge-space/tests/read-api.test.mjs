import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../supabase/functions/knowledge-space-read/handler.mjs';

test('limits list page size and uses an RLS-scoped public key', async () => {
  let target, headers;
  const fetcher = async (url, options) => { target = url; headers = options.headers; return new Response(JSON.stringify([{id:'demo'}]), { status:200,headers:{'content-type':'application/json'} }); };
  const response = await createHandler({url:'https://example.supabase.co',anonKey:'public-test'},fetcher)(new Request('https://site.test/entities?limit=999'));
  assert.equal(response.status,200);
  assert.match(target,/limit=50/);
  assert.equal(headers.apikey,'public-test');
  assert.equal(headers.Authorization,'Bearer public-test');
});
test('rejects invalid entity IDs without calling backend', async () => {
  const handler = createHandler({url:'https://example.supabase.co',anonKey:'public-test'},()=>{ throw Error('unexpected'); });
  assert.equal((await handler(new Request('https://site.test/entities/not-a-uuid'))).status,400);
});
test('does not expose privileged writes', async () => {
  const handler = createHandler({url:'https://example.supabase.co',anonKey:'public-test'},()=>{ throw Error('unexpected'); });
  assert.equal((await handler(new Request('https://site.test/entities',{method:'POST'}))).status,405);
});
test('accepts the Supabase function route prefix', async () => {
  const fetcher=async()=>new Response('[]',{status:200});
  const handler=createHandler({url:'https://example.supabase.co',anonKey:'public-test'},fetcher);
  assert.equal((await handler(new Request('https://site.test/knowledge-space-read/entities'))).status,200);
});
