-- ============================================================
-- BÚSSOLA — registo de perguntas ao assistente
-- Serve dois fins: rate limiting e a analítica
-- "o que as pessoas procuram e não encontram".
-- ============================================================
create table if not exists public.ai_queries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  question text not null,
  intent text,                       -- intenção detetada (ou null)
  answered boolean not null default false,
  escalated boolean not null default false,  -- encaminhado para profissional
  city text,
  country_id text,
  created_at timestamptz not null default now()
);
comment on table public.ai_queries is 'Perguntas ao assistente. answered=false alimenta o backlog de conteúdo.';

create index if not exists idx_ai_created on public.ai_queries(created_at desc);
create index if not exists idx_ai_unanswered on public.ai_queries(answered) where answered = false;
create index if not exists idx_ai_user_time on public.ai_queries(user_id, created_at desc);

alter table public.ai_queries enable row level security;

-- O utilizador pode inserir as suas perguntas e reler as suas próprias.
-- A leitura agregada (analítica) é feita pelo service_role no painel de admin.
create policy "ai_insert_proprio" on public.ai_queries
  for insert to authenticated
  with check (user_id = (select auth.uid()) or user_id is null);

create policy "ai_select_proprio" on public.ai_queries
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Contagem de pedidos na última hora, para rate limiting na Edge Function.
create or replace function public.ai_recent_count(p_user uuid, p_minutes int default 60)
returns int
language sql
security definer
set search_path = ''
stable
as $$
  select count(*)::int
  from public.ai_queries
  where user_id = p_user
    and created_at > now() - make_interval(mins => p_minutes);
$$;

revoke all on function public.ai_recent_count(uuid, int) from public, anon;
grant execute on function public.ai_recent_count(uuid, int) to service_role;
