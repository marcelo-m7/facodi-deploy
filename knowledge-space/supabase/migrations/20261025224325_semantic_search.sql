-- Public retrieval of explicitly approved embeddings, with PostgreSQL RLS.
create policy ks_approved_embeddings on public.ks_embeddings
for select to anon, authenticated
using (exists (
  select 1 from public.ks_entities e
  where e.id = entity_id and e.status = 'approved'
));
grant select on public.ks_embeddings to anon, authenticated;

create or replace function public.ks_semantic_search(
  query_embedding extensions.vector(384),
  match_count integer default 12
)
returns table (
  id uuid, stable_key text, label text, definition text,
  kind text, domain_weights jsonb, similarity double precision
)
language sql stable security invoker
set search_path = ''
as $$
  select e.id, e.stable_key, e.label, e.definition,
         e.kind, e.domain_weights,
         (1 - (v.embedding OPERATOR(extensions.<=>) query_embedding))::double precision as similarity
  from public.ks_embeddings v
  join public.ks_entities e on e.id = v.entity_id
  where e.status = 'approved' and v.model_id = 'gte-small'
  order by v.embedding OPERATOR(extensions.<=>) query_embedding
  limit least(greatest(coalesce(match_count,12),1),12)
$$;

revoke all on function public.ks_semantic_search(extensions.vector(384),integer) from public;
grant execute on function public.ks_semantic_search(extensions.vector(384),integer) to anon, authenticated;
