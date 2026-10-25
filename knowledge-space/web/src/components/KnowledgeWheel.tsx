import type {Entity} from '../types';
import {DOMAINS,mixColor,normalizeWeights} from '../lib/knowledge.mjs';

type Props={entities:Entity[];selected:string|null;onSelect:(id:string)=>void};
const center=240;
function polar(angle:number,r:number){return {x:center+Math.cos(angle)*r,y:center+Math.sin(angle)*r};}
function arc(start:number,end:number){const a=polar(start,210),b=polar(end,210),c=polar(end,110),d=polar(start,110);return `M${a.x},${a.y} A210,210 0 0,1 ${b.x},${b.y} L${c.x},${c.y} A110,110 0 0,0 ${d.x},${d.y} Z`;}
const angles=[-Math.PI*0.75,-Math.PI*0.25,Math.PI*0.25,Math.PI*0.75];
export default function KnowledgeWheel({entities,selected,onSelect}:Props){
  return <svg className="wheel" viewBox="0 0 480 480" aria-label="Círculo cromático interativo dos conhecimentos" role="group">
    <circle cx="240" cy="240" r="225" fill="none" stroke="var(--line)" strokeWidth="1" />
    {DOMAINS.map((domain,i)=><g key={domain.key}>
      <path d={arc(-Math.PI+i*Math.PI/2,-Math.PI+(i+1)*Math.PI/2)} fill={domain.color} opacity=".12" stroke="var(--surface)" strokeWidth="2"/>
      <text x={polar(angles[i],226).x} y={polar(angles[i],226).y} textAnchor="middle" fill="var(--text)" fontSize="12" fontWeight="600">{domain.label}</text>
    </g>)}
    {[135,165,195].map(r=><circle key={r} cx="240" cy="240" r={r} stroke="var(--line)" strokeDasharray="3 6" fill="none"/>)}
    {entities.map((entity,index)=>{
      const weights=normalizeWeights(entity.domain_weights);
      let x=0,y=0;
      DOMAINS.forEach((d,i)=>{x+=Math.cos(angles[i])*weights[d.key];y+=Math.sin(angles[i])*weights[d.key];});
      const angle=Math.atan2(y,x)+(index%3-1)*.085;
      const radial=135+Math.min(70,entity.granularity*16)+(index%3)*8;
      const pos=polar(angle,radial);
      const isSelected=entity.id===selected;
      return <g key={entity.id} role="button" tabIndex={0} aria-label={`Explorar ${entity.label}`} onClick={()=>onSelect(entity.id)} onKeyDown={e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();onSelect(entity.id);}}} className="knowledge-node">
        {isSelected&&<circle cx={pos.x} cy={pos.y} r="15" fill="none" stroke={mixColor(entity.domain_weights)} strokeWidth="2"/>}
        <circle cx={pos.x} cy={pos.y} r={isSelected?9:7} fill={mixColor(entity.domain_weights)} stroke="var(--surface)" strokeWidth="2"/>
        <title>{entity.label}</title>
      </g>;
    })}
    <circle cx="240" cy="240" r="91" fill="var(--surface)" stroke="var(--line)" strokeWidth="1.5"/>
    <text x="240" y="226" textAnchor="middle" className="wheel-center-label">KNOWLEDGE</text>
    <text x="240" y="252" textAnchor="middle" className="wheel-center-main">SPACE</text>
    <text x="240" y="275" textAnchor="middle" className="wheel-center-sub">FACODI / PILOTO</text>
  </svg>;
}
