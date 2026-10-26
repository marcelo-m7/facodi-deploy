import test from 'node:test';
import assert from 'node:assert/strict';
import {semanticSearch} from '../web/src/lib/semantic.mjs';

test('semantic search encodes the query and keeps similarity scores',async()=>{
  let requested;
  const fetcher=async url=>{requested=url;return new Response(JSON.stringify([{id:'a',similarity:.91,label:'Derivadas'}]),{status:200});};
  const results=await semanticSearch(' taxa de mudança ','https://api.test',fetcher);
  assert.match(requested,/q=taxa\+de\+mudan%C3%A7a/);
  assert.equal(results[0].similarity,.91);
});
test('semantic search reports unavailable API rather than claiming a match',async()=>{
  await assert.rejects(semanticSearch('derivada','https://api.test',async()=>new Response('{}',{status:503})),/indisponível/);
});
test('blank semantic query is rejected before network call',async()=>{
  await assert.rejects(semanticSearch('  ','https://api.test',()=>{throw Error('network');}),/consulta vazia/);
});
