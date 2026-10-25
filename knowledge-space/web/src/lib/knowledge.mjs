export const DOMAINS = [
  { key: 'languages', label: 'Linguagens', color: '#8b5cf6' },
  { key: 'mathematics', label: 'Matemática', color: '#3b82f6' },
  { key: 'nature', label: 'Natureza', color: '#17aa88' },
  { key: 'humanities', label: 'Humanas', color: '#f59e0b' },
];

export function normalizeWeights(weights = {}) {
  const values = DOMAINS.map(({ key }) => Number.isFinite(+weights[key]) ? Math.max(0, +weights[key]) : 0);
  const sum = values.reduce((a,b)=>a+b,0);
  return Object.fromEntries(DOMAINS.map((d,i)=>[d.key, sum ? values[i]/sum : 0]));
}

export function mixColor(weights = {}) {
  const norm = normalizeWeights(weights);
  const rgb = [0,1,2].map(index => Math.round(DOMAINS.reduce((sum,d)=>sum + parseInt(d.color.slice(1+index*2,3+index*2),16)*norm[d.key],0)));
  return '#' + rgb.map(n => n.toString(16).padStart(2,'0')).join('');
}

export function graphNeighbors(id, edges = []) {
  return edges.filter(edge => edge.source_id === id && edge.status === 'approved');
}

export function searchEntities(entities = [], query = '') {
  const term = query.trim().toLocaleLowerCase();
  if (!term) return entities;
  return entities.filter(e => `${e.label} ${e.definition || ''}`.toLocaleLowerCase().includes(term));
}
