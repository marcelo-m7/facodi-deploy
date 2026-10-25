import type {Entity,Relation} from '../types';
import {mixColor} from '../lib/knowledge.mjs';
type Props={entities:Entity[];relations:Relation[];selected:string|null;onSelect:(id:string)=>void};
export default function KnowledgeGraph({entities,relations,selected,onSelect}:Props){
  const positioned=entities.map((entity,index)=>{const a=-Math.PI/2+index*2*Math.PI/entities.length;return {...entity,x:300+Math.cos(a)*205,y:250+Math.sin(a)*183};});
  const lookup=new Map(positioned.map(e=>[e.id,e]));
  return <svg className="graph" viewBox="0 0 600 500" role="group" aria-label="Grafo das relações do conhecimento">
    {relations.map(edge=>{const a=lookup.get(edge.source_id),b=lookup.get(edge.target_id);if(!a||!b)return null;return <line key={edge.id} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={selected&&(selected===a.id||selected===b.id)?'#58c9c0':'var(--graph-line)'} strokeWidth={selected&&(selected===a.id||selected===b.id)?2.5:1.4} opacity={selected&&(selected!==a.id&&selected!==b.id)?.25:.8}><title>{edge.relation_type}</title></line>;})}
    {positioned.map(e=><g className="graph-node" key={e.id} role="button" tabIndex={0} aria-label={`Explorar ${e.label}`} onClick={()=>onSelect(e.id)} onKeyDown={ev=>{if(ev.key==='Enter'||ev.key===' '){ev.preventDefault();onSelect(e.id);}}}>
      <circle cx={e.x} cy={e.y} r={selected===e.id?19:14} fill="var(--surface)" stroke={mixColor(e.domain_weights)} strokeWidth={selected===e.id?5:3}/>
      <circle cx={e.x} cy={e.y} r="5" fill={mixColor(e.domain_weights)}/>
      <text x={e.x} y={e.y+31} textAnchor="middle" fill="var(--text)" fontSize="11" fontWeight={selected===e.id?700:500}>{e.label}</text>
    </g>)}
  </svg>;
}
