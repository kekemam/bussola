-- ============================================================
-- Registo de empresa: criar a empresa e o vínculo do dono têm de
-- acontecer juntos.
--
-- O problema: `company_members` não tinha política de escrita, por
-- isso quem registava uma empresa criava a linha em `companies` e
-- falhava a seguir — ficando sem acesso à própria empresa. Só
-- apareceu quando o registo de contas passou a funcionar.
--
-- Não basta abrir um INSERT a `company_members`: se qualquer pessoa
-- pudesse inserir (company_id, user_id=eu), bastava adivinhar o id de
-- outra empresa para se juntar a ela. As duas escritas passam por
-- esta função, numa só transação.
-- ============================================================
create or replace function public.registar_empresa(
  p_name text,
  p_category text,
  p_city text default null,
  p_nif text default null,
  p_email text default null,
  p_about text default null
)
returns public.companies
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_co  public.companies%rowtype;
begin
  if v_uid is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  if coalesce(trim(p_name),'') = '' then
    raise exception 'nome_obrigatorio' using errcode = '22023';
  end if;

  -- a verificação começa sempre em 'pending': ninguém se auto-verifica
  insert into public.companies (name, category, city, nif, email, about, verification)
  values (trim(p_name), p_category, p_city, p_nif, p_email, p_about, 'pending')
  returning * into v_co;

  insert into public.company_members (company_id, user_id, role)
  values (v_co.id, v_uid, 'owner');

  return v_co;
end;
$$;

comment on function public.registar_empresa(text,text,text,text,text,text) is
  'Único caminho para registar empresa. SECURITY DEFINER e chamável por '
  'authenticated de propósito: cria a empresa e o vínculo do dono na mesma '
  'transação, o que o cliente não pode fazer sozinho sem abrir a porta a '
  'juntar-se a empresas alheias. O linter assinala como 0029 (WARN) — é o '
  'comportamento pretendido. A função força verification=pending.';

revoke all on function public.registar_empresa(text,text,text,text,text,text) from public, anon;
grant execute on function public.registar_empresa(text,text,text,text,text,text) to authenticated, service_role;

-- A criação directa em `companies` deixa de ser necessária: passa a
-- ser sempre pela função, para não voltar a haver empresas órfãs.
drop policy if exists "criar_empresa" on public.companies;
