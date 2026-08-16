-- ============================================================
-- Administração da plataforma
--
-- O painel de admin é um ficheiro estático servido ao cliente, por
-- isso não pode usar a service_role: essa chave ignora todo o RLS e
-- ficaria pública. Em vez disso, o administrador autentica-se
-- normalmente e o acesso alargado vem de estar nesta tabela.
-- ============================================================
create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'admin' check (role in ('admin','moderator')),
  created_at timestamptz not null default now()
);
comment on table public.platform_admins is
  'Quem tem acesso à consola. Só o service_role pode inserir: ninguém se promove a si próprio.';

alter table public.platform_admins enable row level security;

-- Cada pessoa vê apenas a sua própria linha. Sem isto, a política de
-- admin nas outras tabelas não conseguiria confirmar nada; com isto,
-- não há recursão porque esta política não consulta mais nenhuma tabela.
create policy "ve_a_sua_linha_de_admin" on public.platform_admins
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Promover alguém é operação de servidor.
revoke insert, update, delete on public.platform_admins from anon, authenticated;

-- ------------------------------------------------------------
-- Acesso alargado do administrador
-- ------------------------------------------------------------
create policy "admin_ve_todas_as_empresas" on public.companies
  for select to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

create policy "admin_modera_empresas" on public.companies
  for update to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

create policy "admin_ve_todos_os_anuncios" on public.listings
  for select to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

create policy "admin_modera_anuncios" on public.listings
  for update to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

-- Destaques: leitura para contabilidade. A escrita continua fechada
-- a toda a gente excepto o service_role, administradores incluídos —
-- receita não se cria a partir do navegador.
create policy "admin_ve_todos_os_destaques" on public.boosts
  for select to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

create policy "admin_ve_perguntas" on public.ai_queries
  for select to authenticated
  using (exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

-- ------------------------------------------------------------
-- O trigger que impede a auto-verificação passa a abrir excepção
-- para administradores, que são precisamente quem verifica.
-- ------------------------------------------------------------
create or replace function public.travar_verificacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.verification is distinct from old.verification then
    if not exists (select 1 from public.platform_admins a where a.user_id = auth.uid()) then
      raise exception 'verificacao_reservada_a_administracao' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.travar_verificacao() from public, anon, authenticated;
