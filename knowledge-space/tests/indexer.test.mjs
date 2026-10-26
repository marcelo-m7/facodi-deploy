import test from 'node:test';
import assert from 'node:assert/strict';
import {createIndexerHandler} from '../supabase/functions/knowledge-space-index/handler.mjs';

const env={url:'https://example.supabase.co',serviceKey:'private-test-key'};
test('indexing denies anonymous requests before reading data',async()=>{
  const handler=createIndexerHandler(env,()=>{throw Error('network called');},()=>{throw Error('embedder called');});
  const res=await handler(new Request('https://example.test',{method:'POST'}));
  assert.equal(res.status,401);
});
test('indexer stores 384-dimensional vectors with model and digest',async()=>{
  const calls=[];
  const fetcher=async(url,opts)=>{
    calls.push({url,opts});
    if(url.includes('ks_entities'))return new Response(JSON.stringify([{id:'abc',label:'Derivadas',definition:'Taxa de variação'}]),{status:200});
    if(url.includes('ks_embeddings?'))return new Response('[]',{status:200});
    return new Response('[]',{status:201});
  };
  const handler=createIndexerHandler(env,fetcher,async()=>Array(384).fill(.1),async()=> 'abc123');
  const res=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer private-test-key'}}));
  assert.equal(res.status,200);
  assert.equal((await res.json()).indexed,1);
  const inserted=JSON.parse(calls.find(x=>x.opts.method==='POST').opts.body);
  assert.equal(JSON.parse(inserted.embedding).length,384);
  assert.equal(inserted.model_id,'gte-small');
  assert.equal(inserted.content_hash,'abc123');
});
test('indexer skips unchanged source revisions',async()=>{
  let writes=0;
  const fetcher=async(url,opts)=>{
    if(url.includes('ks_entities'))return new Response(JSON.stringify([{id:'abc',label:'Derivadas',definition:'Taxa de variação'}]),{status:200});
    if(url.includes('ks_embeddings?'))return new Response(JSON.stringify([{entity_id:'abc',content_hash:'same'}]),{status:200});
    if(opts.method==='POST')writes++;
    return new Response('[]',{status:201});
  };
  const handler=createIndexerHandler(env,fetcher,async()=>{throw Error('unnecessary embedding');},async()=> 'same');
  const res=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer private-test-key'}}));
  assert.equal((await res.json()).indexed,0);
  assert.equal(writes,0);
});
