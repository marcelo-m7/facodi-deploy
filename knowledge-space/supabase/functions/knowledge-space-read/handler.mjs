const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const JSON_HEADERS = { 'content-type': 'application/json', 'access-control-allow-origin':'*', 'access-control-allow-methods':'GET, OPTIONS' };
const send = (body,status=200)=>new Response(JSON.stringify(body),{status,headers:JSON_HEADERS});

export function createHandler({url,anonKey}, fetcher = fetch) {
  return async request => {
    if (request.method === 'OPTIONS') return new Response(null,{status:204,headers:JSON_HEADERS});
    if (request.method !== 'GET') return send({error:'method_not_allowed'},405);
    if (!url || !anonKey) return send({error:'not_configured'},503);
    const parsed = new URL(request.url);
    const path = parsed.pathname.split('/').filter(Boolean).filter((segment,index) => !(index===0 && segment==='knowledge-space-read'));
    let table, params = new URLSearchParams({select:'*'});
    if (path.length===1 && path[0]==='entities') {
      table='ks_entities';
      const limit = Math.max(1,Math.min(50,Number.parseInt(parsed.searchParams.get('limit')||'30',10)||30));
      params.set('limit',String(limit));
      params.set('order','label.asc');
    } else if (path.length===2 && path[0]==='entities') {
      if (!UUID.test(path[1])) return send({error:'invalid_id'},400);
      table='ks_entities';params.set('id',`eq.${path[1]}`);params.set('limit','1');
    } else if (path.length===1 && path[0]==='relations') {
      const id=parsed.searchParams.get('entity_id')||'';
      if (!UUID.test(id)) return send({error:'invalid_id'},400);
      table='ks_relations';params.set('or',`(source_id.eq.${id},target_id.eq.${id})`);params.set('limit','100');
    } else if (path.length===1 && path[0]==='search') {
      const q=(parsed.searchParams.get('q')||'').trim();
      if (!q || q.length>120) return send({error:'invalid_query'},400);
      table='ks_entities';params.set('label',`ilike.*${q.replace(/[%*,()]/g,'')}*`);params.set('limit','30');
    } else return send({error:'not_found'},404);
    try {
      const upstream=await fetcher(`${url.replace(/\/$/,'')}/rest/v1/${table}?${params}`,{headers:{apikey:anonKey,Authorization:`Bearer ${anonKey}`}});
      if (!upstream.ok) return send({error:'upstream_unavailable'},502);
      return send(await upstream.json());
    } catch {return send({error:'upstream_unavailable'},502);}
  };
}
