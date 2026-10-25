const headers={ 'content-type':'application/json', 'access-control-allow-origin':'*', 'access-control-allow-methods':'POST,OPTIONS', 'access-control-allow-headers':'authorization,content-type'};
const respond=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
const KINDS=new Set(['concept','competency','objective','curriculum','resource']);

function validate(input){
  if(!input||typeof input!=='object')return false;
  try{const u=new URL(input.source_uri);if(!['https:','http:'].includes(u.protocol))return false;}catch{return false;}
  if(!/^[0-9a-f]{16,128}$/i.test(input.content_hash||''))return false;
  if(!Array.isArray(input.entities)||input.entities.length<1||input.entities.length>30)return false;
  return input.entities.every(e=>e&&typeof e==='object'&&KINDS.has(e.kind)&&
    typeof e.stable_key==='string'&&/^[a-z0-9:_-]{3,100}$/.test(e.stable_key)&&
    typeof e.label==='string'&&e.label.trim().length>1&&e.label.length<=180&&
    (e.definition===undefined||(typeof e.definition==='string'&&e.definition.length<=3000))&&
    (e.domain_weights===undefined||(e.domain_weights&&typeof e.domain_weights==='object'&&!Array.isArray(e.domain_weights)&&Object.entries(e.domain_weights).every(([domain,weight])=>['languages','mathematics','nature','humanities'].includes(domain)&&typeof weight==='number'&&Number.isFinite(weight)&&weight>=0&&weight<=1)))&&
    !('status' in e)&&!('id' in e));
}

export function createIngestionHandler({url,serviceKey},fetcher=fetch){
  return async request=>{
    if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
    if(request.method!=='POST')return respond({error:'method_not_allowed'},405);
    if(!url||!serviceKey)return respond({error:'not_configured'},503);
    if(request.headers.get('Authorization')!==`Bearer ${serviceKey}`)return respond({error:'unauthorized'},401);
    let payload;
    try{payload=await request.json();}catch{return respond({error:'invalid_json'},400);}
    if(!validate(payload))return respond({error:'invalid_payload'},400);
    const base=`${url.replace(/\/$/,'')}/rest/v1/`;
    const auth={apikey:serviceKey,Authorization:`Bearer ${serviceKey}`,'content-type':'application/json'};
    const requestDb=async(path,options={})=>{
      const response=await fetcher(`${base}${path}`,{...options,headers:{...auth,...options.headers}});
      if(!response.ok)throw new Error(`db_${response.status}`);
      return response.json();
    };
    try{
      const idQuery=new URLSearchParams({select:'id,status',source_uri:`eq.${payload.source_uri}`,content_hash:`eq.${payload.content_hash}`,limit:'1'});
      const existing=await requestDb(`ks_ingestion_runs?${idQuery}`);
      if(existing.length)return respond({job_id:existing[0].id,status:existing[0].status,replayed:true});
      const [job]=await requestDb('ks_ingestion_runs?select=id,status',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify({source_uri:payload.source_uri,content_hash:payload.content_hash,status:'pending'})});
      const candidates=payload.entities.map(e=>({stable_key:e.stable_key,kind:e.kind,label:e.label.trim(),definition:e.definition||'',domain_weights:e.domain_weights||{},source_uri:payload.source_uri,status:'proposed'}));
      try{
        await requestDb('ks_entities?on_conflict=stable_key',{method:'POST',headers:{Prefer:'resolution=ignore-duplicates,return=representation'},body:JSON.stringify(candidates)});
        await requestDb(`ks_ingestion_runs?id=eq.${job.id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:JSON.stringify({status:'completed'})});
        return respond({job_id:job.id,status:'completed',proposed_count:candidates.length},202);
      }catch{
        await requestDb(`ks_ingestion_runs?id=eq.${job.id}`,{method:'PATCH',headers:{Prefer:'return=representation'},body:JSON.stringify({status:'failed',error_code:'proposal_persistence_failed'})}).catch(()=>{});
        return respond({job_id:job.id,status:'failed'},502);
      }
    }catch{return respond({error:'ingestion_unavailable'},502);}
  };
}
