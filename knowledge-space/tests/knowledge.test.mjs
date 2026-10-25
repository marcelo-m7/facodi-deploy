import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeWeights, mixColor, graphNeighbors, searchEntities } from '../web/src/lib/knowledge.mjs';

test('domain weights remain four dimensional and sum to one', () => {
  assert.deepEqual(normalizeWeights({ mathematics: 2, nature: 1 }), { languages: 0, mathematics: 2/3, nature: 1/3, humanities: 0 });
  assert.deepEqual(normalizeWeights({ mathematics: -2 }), { languages: 0, mathematics: 0, nature: 0, humanities: 0 });
});
test('color projection does not mutate knowledge weights', () => {
  const input = Object.freeze({ languages: 0, mathematics: .8, nature: .2, humanities: 0 });
  assert.match(mixColor(input), /^#[0-9a-f]{6}$/);
  assert.equal(input.mathematics, .8);
});
test('graph neighbors are directional and review-limited', () => {
  const edges = [{ source_id: 'a',target_id:'b',relation_type:'prerequisite_of',status:'approved' },{source_id:'a',target_id:'c',status:'proposed'}];
  assert.deepEqual(graphNeighbors('a', edges).map(e=>e.target_id), ['b']);
});
test('search respects labels and descriptions without claiming equivalence', () => {
  assert.deepEqual(searchEntities([{id:'a',label:'Funções',definition:'domínio e imagem'}, {id:'b',label:'Limites',definition:'aproximação'}], 'imagem').map(e=>e.id), ['a']);
});
