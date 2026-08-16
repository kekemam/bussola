-- ============================================================
-- Denúncias
--
-- A app já deixa denunciar anúncios de habitação e conversas, mas
-- não havia onde as guardar: a fila de moderação da consola vivia
-- só em memória. Passa a existir.
-- ============================================================
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  target_kind text not null check (target_kind in ('listing','company','message','post','user')),
  target_id text not null,                 -- texto, porque nem tudo é uuid
  target_label text,                       -- o que estava no ecrã, para o moderador ter contexto
  reason text not null,
  details text,
  reporter_id uuid references auth.users(id) on delete set null,
  status text not null default 'open'
    check (status in ('open','reviewing','resolved','dismissed')),
  resolution text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
comment on table public.reports is 'Fila de moderação. Alimentada pelas denúncias feitas na app.';

create index if not exists idx_reports_abertas on public.reports(created_at desc) where status in ('open','reviewing');
create index if not exists idx_reports_alvo on public.reports(target_kind, target_id);

alter table public.reports enable row level security;

-- Qualquer pessoa autenticada pode denunciar.
create policy "denunciar" on public.reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()) or reporter_id is null);

-- Quem denuncia acompanha a sua denúncia.
create policy "ve_as_suas_denuncias" on public.reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

-- A moderação é da administração.
create policy "admin_ve_denuncias" on public.reports
  for select to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

create policy "admin_resolve_denuncias" on public.reports
  for update to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

-- Ninguém apaga denúncias pelo cliente: o histórico de moderação
-- tem de resistir a quem tem interesse em o fazer desaparecer.
revoke delete on public.reports from anon, authenticated;

-- ============================================================
-- O ecrã de utilizadores precisa de ver todos os perfis.
-- ============================================================
create policy "admin_ve_perfis" on public.profiles
  for select to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

-- ============================================================
-- Vista da fila de moderação, já ordenada por urgência.
-- ============================================================
create or replace view public.v_fila_moderacao
with (security_invoker = true) as
select
  r.id, r.target_kind, r.target_id, r.target_label, r.reason, r.details,
  r.status, r.created_at,
  count(*) over (partition by r.target_kind, r.target_id) as denuncias_no_alvo
from public.reports r
where r.status in ('open','reviewing')
order by denuncias_no_alvo desc, r.created_at asc;

grant select on public.v_fila_moderacao to authenticated, service_role;
