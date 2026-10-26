export async function semanticSearch(rawQuery,apiUrl,fetcher=fetch){
  const query=rawQuery.trim();
  if(!query)throw new Error('consulta vazia');
  const params=new URLSearchParams({q:query});
  const response=await fetcher(`${apiUrl.replace(/\/$/,'')}/semantic-search?${params}`);
  if(!response.ok)throw new Error('Pesquisa semântica indisponível');
  const data=await response.json();
  if(!Array.isArray(data))throw new Error('Pesquisa semântica indisponível');
  return data;
}
