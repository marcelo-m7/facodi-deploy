import test from 'node:test';
import assert from 'node:assert/strict';
import {createIngestionHandler} from '../supabase/functions/knowledge-space-ingest/handler.mjs';

const env={url:'https://example.supabase.co',serviceKey:'private-test-key'};
test('rejects unprivileged ingestion', async()=>{
  const handler=createIngestionHandler(env,()=>{throw new Error('unexpected network');});
  const response=await handler(new Request('https://example.test',{method:'POST',body:JSON.stringify({})}));
  assert.equal(response.status,401);
});
test('validates source and refuses to accept approved status from caller',async()=>{
  const handler=createIngestionHandler(env,()=>{throw new Error('unexpected network');});
  const payload={source_uri:'https://example.edu/source',content_hash:'1234567890abcdef',entities:[{stable_key:'x',kind:'concept',label:'Demo',status:'approved'}]};
  const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer private-test-key'},body:JSON.stringify(payload)}));
  assert.equal(response.status,400);
});
test('replayed source revision does not write proposals twice',async()=>{
  let writes=0;
  const fetcher=async(url,options)=>{
    if(!options.method||options.method==='GET') return new Response(JSON.stringify([{id:'old',status:'completed'}]),{status:200});
    writes++;return new Response('[]',{status:201});
  };
  const handler=createIngestionHandler(env,fetcher);
  const payload={source_uri:'https://example.edu/source',content_hash:'1234567890abcdef',entities:[{stable_key:'demo:new',kind:'concept',label:'Novo'}]};
  const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer private-test-key'},body:JSON.stringify(payload)}));
  assert.equal(response.status,200);
  assert.equal(writes,0);
});
test('rejects malformed domain weight vectors', async()=>{
  const handler=createIngestionHandler(env,()=>{throw Error('unexpected');});
  const payload={source_uri:'https://example.edu/source',content_hash:'1234567890abcdef',entities:[{stable_key:'demo:invalid',kind:'concept',label:'Conceito',domain_weights:{mathematics:-5}}]};
  const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer private-test-key'},body:JSON.stringify(payload)}));
  assert.equal(response.status,400);
});
