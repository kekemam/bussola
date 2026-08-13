-- ============================================================
-- BÚSSOLA — schema base do utilizador
-- Multi-tenant por utilizador: cada pessoa só vê os seus dados.
-- ============================================================

-- Perfil (1:1 com auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  country_id text,                       -- ao | cv | gw | mz | st | other
  city text,
  situations text[] not null default '{}',
  locale text not null default 'pt-PT',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.profiles is 'Perfil do utilizador da Bússola. Espelha o onboarding.';

-- Progresso do plano de chegada
create table if not exists public.plan_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  step_id text not null,                 -- ps1..ps5
  done_at timestamptz not null default now(),
  primary key (user_id, step_id)
);

-- Checklist dos processos de documentação
create table if not exists public.doc_checklist (
  user_id uuid not null references auth.users(id) on delete cascade,
  doc_id text not null,                  -- nif | niss | aima-res | ...
  item_index int not null,
  done boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, doc_id, item_index)
);

-- Guardados (vagas, casas, eventos, grupos)
create table if not exists public.saved_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('job','home','event','group','pro')),
  item_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, item_id)
);

-- Candidaturas a vagas
create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id text not null,
  status text not null default 'Candidatura enviada'
    check (status in ('Guardada','Candidatura enviada','Em análise','Entrevista','Oferta','Rejeitada')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, job_id)
);

-- ------------------------------------------------------------
-- RLS: cada utilizador só acede às suas próprias linhas
-- ------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.plan_progress  enable row level security;
alter table public.doc_checklist  enable row level security;
alter table public.saved_items    enable row level security;
alter table public.applications   enable row level security;

create policy "perfil_proprio" on public.profiles
  for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "plano_proprio" on public.plan_progress
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "checklist_propria" on public.doc_checklist
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "guardados_proprios" on public.saved_items
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "candidaturas_proprias" on public.applications
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Criar perfil automaticamente ao registar
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Índices
create index if not exists idx_saved_user_kind on public.saved_items(user_id, kind);
create index if not exists idx_apps_user on public.applications(user_id);
