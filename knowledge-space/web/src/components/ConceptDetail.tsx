import type {Entity,Relation} from '../types';
import {DOMAINS,normalizeWeights} from '../lib/knowledge.mjs';
type Props={entity:Entity|null;entities:Entity[];relations:Relation[];onSelect:(id:string)=>void};
const relationLabels:Record<string,string>={prerequisite_of:'Pré-requisito para',applied_in:'Aplicado em',develops_competency:'Desenvolve',addresses_objective:'Contribui para',part_of:'Parte de',aligned_to:'Alinhado com',references_resource:'Referencia'};
export default function ConceptDetail({entity,entities,relations,onSelect}:Props){
  if(!entity)return <div className="empty-detail"><span className="empty-mark">◎</span><h3>Explora o mapa</h3><p>Seleciona um ponto no círculo ou um conceito da lista para conhecer as suas relações.</p></div>;
  const weights=normalizeWeights(entity.domain_weights);
  const links=relations.filter(e=>e.source_id===entity.id||e.target_id===entity.id);
  return <div className="detail-content">
    <div className="eyebrow">{entity.kind==='competency'?'COMPETÊNCIA':entity.kind==='objective'?'OBJETIVO DE APRENDIZAGEM':'CONCEITO'} / {entity.stable_key.replace('demo:','').toUpperCase()}</div>
    <h2>{entity.label}</h2><p className="definition">{entity.definition}</p>
    <div className="section-label">ASSINATURA DO CONHECIMENTO</div>
    <div className="weight-track">{DOMAINS.map(d=><div key={d.key} style={{width:`${weights[d.key]*100}%`,background:d.color}}/>)}</div>
    <div className="weight-list">{DOMAINS.map(d=><div key={d.key}><i style={{background:d.color}}/>{d.label}<b>{Math.round(weights[d.key]*100)}%</b></div>)}</div>
    <div className="section-label relations-title">RELAÇÕES FORMALIZADAS <span>{links.length}</span></div>
    <div className="relation-list">{links.length?links.map(link=>{const out=link.source_id===entity.id;const other=entities.find(e=>e.id===(out?link.target_id:link.source_id));return other?<button key={link.id} onClick={()=>onSelect(other.id)}><small>{out?relationLabels[link.relation_type]||link.relation_type:'Deriva de / relacionado'}</small><strong>{other.label}</strong><span>↗</span></button>:null;}):<p className="muted">Sem relações registadas neste piloto.</p>}</div>
    <div className="source-note">Origem: {entity.source_uri || 'Não especificada'} · Demonstração não certificada</div>
  </div>;
}
