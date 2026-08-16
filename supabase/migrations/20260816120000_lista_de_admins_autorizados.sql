-- ============================================================
-- Arranque da administração
--
-- Problema do primeiro administrador: `platform_admins` não aceita
-- escrita do cliente (de propósito), por isso ninguém se promove —
-- incluindo a primeira pessoa, que ainda não tem conta.
--
-- Solução: uma lista de emails autorizados. Quando a conta com esse
-- email for criada, seja por que via for, é promovida automaticamente.
-- A lista é escrita apenas pelo service_role.
--
-- Vantagem sobre criar a conta à mão: não é preciso ninguém tocar
-- numa palavra-passe. A pessoa define a sua credencial pelos canais
-- normais e o acesso aparece sozinho.
-- ============================================================
create table if not exists public.admin_allowlist (
  email text primary key,
  role text not null default 'admin' check (role in ('admin','moderator')),
  note text,
  created_at timestamptz not null default now()
);
comment on table public.admin_allowlist is
  'Emails que se tornam administradores ao criar conta. Só o service_role escreve. '
  'RLS ligado SEM políticas de propósito: nega tudo ao cliente. O linter assinala '
  'isto como rls_enabled_no_policy (INFO) — é o comportamento pretendido, não '
  'acrescentar políticas.';

alter table public.admin_allowlist enable row level security;
-- Sem políticas: ninguém lê nem escreve pelo cliente. Saber quem está
-- na lista já é informação útil a quem quisesse atacar a plataforma.
revoke all on public.admin_allowlist from anon, authenticated;

-- Promoção no momento em que a conta nasce.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;

  select a.role into v_role
    from public.admin_allowlist a
   where lower(a.email) = lower(new.email);

  if v_role is not null then
    insert into public.platform_admins (user_id, role)
    values (new.id, v_role)
    on conflict (user_id) do nothing;
  end if;

  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Caso a conta já exista quando o email entra na lista, promove na hora.
create or replace function public.promover_da_lista()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  with promovidos as (
    insert into public.platform_admins (user_id, role)
    select u.id, a.role
      from auth.users u
      join public.admin_allowlist a on lower(a.email) = lower(u.email)
    on conflict (user_id) do nothing
    returning 1
  ) select count(*) into n from promovidos;
  return n;
end;
$$;
revoke all on function public.promover_da_lista() from public, anon, authenticated;
grant execute on function public.promover_da_lista() to service_role;

-- Nota: os emails autorizados são DADOS, não schema. São inseridos
-- fora das migrações, para não ficarem versionados no repositório.
