import type {Entity,Relation} from './types';
const API = import.meta.env.VITE_KS_API_URL || 'https://bhfywztfyidvrlarebmg.supabase.co/functions/v1/knowledge-space-read';
async function get<T>(path:string):Promise<T>{
  const response=await fetch(`${API}${path}`);
  if(!response.ok) throw new Error(`API indisponível (${response.status})`);
  return response.json() as Promise<T>;
}
export const fetchEntities=()=>get<Entity[]>('/entities?limit=50');
export const fetchRelations=async(ids:string[]):Promise<Relation[]>=>{
  const batches=await Promise.all(ids.map(id=>get<Relation[]>(`/relations?entity_id=${encodeURIComponent(id)}`)));
  return [...new Map(batches.flat().map(edge=>[edge.id,edge])).values()];
};
