-- Experimental FACODI Knowledge Space. Editorial Odoo tables are not affected.
create extension if not exists vector with schema extensions;

create table if not exists public.ks_entities (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  kind text not null check (kind in ('concept','competency','objective','curriculum','resource')),
  label text not null,
  definition text not null default '',
  domain_weights jsonb not null default '{}'::jsonb,
  granularity integer not null default 1 check (granularity between 0 and 10),
  source_uri text,
  status text not null default 'proposed' check (status in ('proposed','approved','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.ks_relations (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.ks_entities(id),
  target_id uuid not null references public.ks_entities(id),
  relation_type text not null check (relation_type in ('prerequisite_of','part_of','applied_in','develops_competency','addresses_objective','references_resource','aligned_to')),
  evidence text not null default '',
  status text not null default 'proposed' check (status in ('proposed','approved','rejected')),
  check (source_id <> target_id),
  unique (source_id,target_id,relation_type)
);

create table if not exists public.ks_coverage (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.ks_entities(id),
  objective_id uuid not null references public.ks_entities(id),
  weight numeric not null check (weight >= 0 and weight <= 1),
  evidence text not null default '',
  status text not null default 'proposed' check (status in ('proposed','approved','rejected')),
  unique (resource_id, objective_id)
);

create table if not exists public.ks_embeddings (
  entity_id uuid not null references public.ks_entities(id) on delete cascade,
  model_id text not null,
  content_hash text not null,
  embedding extensions.vector(384) not null,
  primary key (entity_id,model_id)
);

create table if not exists public.ks_ingestion_runs (
  id uuid primary key default gen_random_uuid(),
  source_uri text not null,
  content_hash text not null,
  status text not null check (status in ('pending','completed','failed')),
  error_code text,
  created_at timestamptz not null default now(),
  unique (source_uri,content_hash)
);

-- A prerequisite cycle is pedagogically contradictory. Detect it at write time.
create or replace function public.ks_no_prerequisite_cycles()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.relation_type = 'prerequisite_of' and exists (
    with recursive reach(id) as (
      select new.target_id
      union
      select r.target_id from public.ks_relations r
      join reach on r.source_id = reach.id
      where r.relation_type = 'prerequisite_of' and r.id is distinct from new.id
    ) select 1 from reach where id = new.source_id
  ) then
    raise exception 'prerequisite cycle';
  end if;
  return new;
end $$;
create trigger ks_prerequisite_cycle_guard before insert or update on public.ks_relations
for each row execute function public.ks_no_prerequisite_cycles();

alter table public.ks_entities enable row level security;
alter table public.ks_relations enable row level security;
alter table public.ks_coverage enable row level security;
alter table public.ks_embeddings enable row level security;
alter table public.ks_ingestion_runs enable row level security;

create policy ks_approved_entities on public.ks_entities for select to anon, authenticated
using (status = 'approved');
create policy ks_approved_relations on public.ks_relations for select to anon, authenticated
using (status = 'approved' and
  exists(select 1 from public.ks_entities e where e.id = source_id and e.status = 'approved') and
  exists(select 1 from public.ks_entities e where e.id = target_id and e.status = 'approved'));
create policy ks_approved_coverage on public.ks_coverage for select to anon, authenticated
using (status = 'approved' and
  exists(select 1 from public.ks_entities e where e.id = resource_id and e.status = 'approved') and
  exists(select 1 from public.ks_entities e where e.id = objective_id and e.status = 'approved'));

grant select on public.ks_entities, public.ks_relations, public.ks_coverage to anon, authenticated;
revoke all on public.ks_embeddings, public.ks_ingestion_runs from anon, authenticated;

create index if not exists ks_embeddings_hnsw on public.ks_embeddings
using hnsw (embedding vector_cosine_ops);
create index if not exists ks_relation_source_idx on public.ks_relations(source_id);
create index if not exists ks_relation_target_idx on public.ks_relations(target_id);
