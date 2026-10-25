import {useEffect,useMemo,useState} from 'react';
import {ArrowUpRight,Atom,BookOpen,ChevronDown,Compass,Layers3,Network,RefreshCw,Search,SlidersHorizontal} from 'lucide-react';
import type {Entity,Relation} from './types';
import {fetchEntities,fetchRelations} from './api';
import {DOMAINS,searchEntities} from './lib/knowledge.mjs';
import KnowledgeWheel from './components/KnowledgeWheel';
import KnowledgeGraph from './components/KnowledgeGraph';
import ConceptDetail from './components/ConceptDetail';

export default function App(){
  const [entities,setEntities]=useState<Entity[]>([]),[relations,setRelations]=useState<Relation[]>([]);
  const [selected,setSelected]=useState<string|null>(null),[view,setView]=useState<'wheel'|'graph'>('wheel');
  const [search,setSearch]=useState(''),[loading,setLoading]=useState(true),[error,setError]=useState<string|null>(null);
  const [version,setVersion]=useState(0);
  useEffect(()=>{let active=true;setLoading(true);setError(null);
    fetchEntities().then(async records=>{const edges=await fetchRelations(records.map(r=>r.id));if(!active)return;
      setEntities(records);setRelations(edges);setSelected(current=>current&&records.some(r=>r.id===current)?current:records.find(r=>r.stable_key==='demo:derivatives')?.id||records[0]?.id||null);
    }).catch(e=>{if(active)setError(e instanceof Error?e.message:'Erro desconhecido');}).finally(()=>{if(active)setLoading(false);});
    return()=>{active=false;};
  },[version]);
  const visible=useMemo(()=>searchEntities(entities,search),[entities,search]);
  const current=entities.find(e=>e.id===selected)||null;
  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><div className="brand-symbol"><Atom size={23} strokeWidth={1.7}/></div><div><strong>FACODI</strong><span>KNOWLEDGE SPACE</span></div></div>
      <div className="workspace-switch"><div><small>WORKSPACE</small><strong>Explorador do conhecimento</strong></div><ChevronDown size={15}/></div>
      <div className="sidebar-caption">EXPLORAR</div>
      <button className="nav-item active" onClick={()=>setView('wheel')}><Compass size={17}/> Mapa de conhecimento</button>
      <button className="nav-item" onClick={()=>setView('graph')}><Network size={17}/> Rede de relações</button>
      <div className="sidebar-caption spaced">DOMÍNIOS</div>
      {DOMAINS.map(d=><div className="domain-item" key={d.key}><span style={{background:d.color}}/>{d.label}<small>{entities.filter(e=>(e.domain_weights?.[d.key]||0)>.2).length}</small></div>)}
      <div className="sidebar-bottom"><div className="pilot-card"><span className="tiny-pulse"/><strong>Ambiente experimental</strong><p>Uma nova forma de conectar conceitos, competências e aprendizagens.</p></div><div className="sidebar-foot">FACODI LAB · V0.1</div></div>
    </aside>
    <main className="main-content">
      <header className="topbar"><div className="breadcrumb"><BookOpen size={16}/><span>Knowledge Space</span><span className="slash">/</span><strong>Visão geral</strong></div><div className="top-actions"><span className="status-dot"/> <span>Supabase conectado</span><a href="https://facodi.com" target="_blank" rel="noreferrer">facodi.com <ArrowUpRight size={14}/></a></div></header>
      <div className="content-padding">
        <div className="hero-top"><div><div className="eyebrow teal">UM UNIVERSO DE CONEXÕES</div><h1>Explora o <em>conhecimento.</em></h1><p>Um espaço vivo de conceitos, competências e relações. Descobre como diferentes áreas se cruzam e constroem novas possibilidades de aprendizagem.</p></div><div className="hero-badge"><Layers3 size={17}/><span>ONTOLOGIA EXPERIMENTAL<br/><b>MATEMÁTICA / PRÉ-CÁLCULO</b></span></div></div>
        <div className="stats"><div><span>CONCEITOS E COMPETÊNCIAS</span><strong>{entities.length.toString().padStart(2,'0')}</strong></div><div><span>CONEXÕES MAPEADAS</span><strong>{relations.length.toString().padStart(2,'0')}</strong></div><div><span>ÁREAS DO CONHECIMENTO</span><strong>04</strong></div><div className="stat-live"><span>ESTADO DA ONTOLOGIA</span><strong><i/> Piloto ativo</strong></div></div>
        <div className="explorer-heading"><div><span className="section-kicker">EXPLORADOR INTERATIVO</span><h2>Atlas do conhecimento</h2></div><div className="view-switch"><button className={view==='wheel'?'selected':''} onClick={()=>setView('wheel')}><Compass size={15}/> Círculo</button><button className={view==='graph'?'selected':''} onClick={()=>setView('graph')}><Network size={15}/> Relações</button></div></div>
        <div className="explorer-grid">
          <section className="map-panel"><div className="panel-top"><div><span className="mini-icon"><SlidersHorizontal size={15}/></span><span>{view==='wheel'?'PROJEÇÃO CROMÁTICA':'GRAFO SEMÂNTICO'}</span></div><span className="badge-quiet">VISUALIZAÇÃO 01 / 02</span></div>
            {loading?<div className="map-loader"><RefreshCw className="spinner"/>A carregar o universo...</div>:error?<div className="map-loader error"><p>{error}</p><button onClick={()=>setVersion(v=>v+1)}>Tentar novamente</button></div>:view==='wheel'?<KnowledgeWheel entities={visible} selected={selected} onSelect={setSelected}/>:<KnowledgeGraph entities={visible} relations={relations} selected={selected} onSelect={setSelected}/>}
            <div className="map-bottom"><span><i className="legend-point"/> {visible.length} elementos visíveis</span><span>Seleciona um ponto para explorar <ArrowUpRight size={13}/></span></div>
          </section>
          <section className="detail-panel"><div className="panel-top"><div><span className="mini-icon"><Atom size={15}/></span><span>DETALHES DO ELEMENTO</span></div><span className="badge-quiet">ONTOLOGIA</span></div><ConceptDetail entity={current} entities={entities} relations={relations} onSelect={setSelected}/></section>
        </div>
        <div className="catalog"><div className="catalog-heading"><div><span className="section-kicker">ÍNDICE DE CONCEITOS</span><h2>Biblioteca de conhecimento</h2></div><div className="search-box"><Search size={17}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Pesquisar conceitos..." aria-label="Pesquisar conceitos"/></div></div>
          <div className="catalog-list">{visible.map(e=><button className={`catalog-row ${selected===e.id?'is-active':''}`} key={e.id} onClick={()=>setSelected(e.id)}><span className="catalog-dot" style={{background:DOMAINS.reduce((best,d)=>(e.domain_weights[d.key]||0)>(e.domain_weights[best.key]||0)?d:best,DOMAINS[0]).color}}/><strong>{e.label}</strong><span>{e.kind==='concept'?'Conceito':e.kind==='competency'?'Competência':'Objetivo'}</span><ArrowUpRight size={16}/></button>)}{!loading&&!visible.length&&<div className="no-results">Nenhum conceito corresponde à pesquisa.</div>}</div>
        </div>
        <footer>FACODI KNOWLEDGE SPACE <span>·</span> Modelo conceptual demonstrativo — não representa equivalências académicas oficiais. <span>© 2026 FACODI</span></footer>
      </div>
    </main>
  </div>;
}
