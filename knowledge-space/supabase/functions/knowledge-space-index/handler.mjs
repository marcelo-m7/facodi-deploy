const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json'}});

async function sha256(content){
  const buffer=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(content));
  return [...new Uint8Array(buffer)].map(x=>x.toString(16).padStart(2,'0')).join('');
}

export function createIndexerHandler({url,serviceKey},fetcher=fetch,embedder=null,hash=sha256){
  return async request=>{
    if(request.method!=='POST')return json({error:'method_not_allowed'},405);
    if(!url||!serviceKey||!embedder)return json({error:'not_configured'},503);
    if(request.headers.get('Authorization')!==`Bearer ${serviceKey}`)return json({error:'unauthorized'},401);
    const base=`${url.replace(/\/$/,'')}/rest/v1/`;
    const headers={apikey:serviceKey,Authorization:`Bearer ${serviceKey}`,'content-type':'application/json'};
    async function requestDb(path,options={}){
      const response=await fetcher(`${base}${path}`,{...options,headers:{...headers,...options.headers}});
      if(!response.ok)throw new Error('db_unavailable');
      return response.status===204?null:response.json();
    }
    try {
      const entities=await requestDb('ks_entities?select=id,label,definition&status=eq.approved&limit=25&order=stable_key.asc');
      const existing=await requestDb('ks_embeddings?select=entity_id,content_hash&model_id=eq.gte-small&limit=1000');
      const hashes=new Map(existing.map(row=>[row.entity_id,row.content_hash]));
      let indexed=0;
      for(const entity of entities){
        const content=`${entity.label}\n${entity.definition}`;
        const digest=await hash(content);
        if(hashes.get(entity.id)===digest)continue;
        const embedding=await embedder(content);
        if(!Array.isArray(embedding)||embedding.length!==384||embedding.some(n=>typeof n!=='number'||!Number.isFinite(n)))return json({error:'invalid_embedding',indexed},502);
        await requestDb('ks_embeddings?on_conflict=entity_id,model_id',{
          method:'POST',headers:{Prefer:'resolution=merge-duplicates,return=representation'},
          body:JSON.stringify({entity_id:entity.id,model_id:'gte-small',content_hash:digest,embedding:JSON.stringify(embedding)})
        });
        indexed++;
      }
      return json({indexed,scanned:entities.length,model:'gte-small'});
    }catch{return json({error:'indexing_unavailable'},502);}
  };
}
