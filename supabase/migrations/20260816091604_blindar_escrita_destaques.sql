-- ============================================================
-- Dupla proteção na receita.
--
-- O RLS já negava a escrita em `boosts` por não existir política,
-- mas o GRANT de INSERT continuava concedido ao papel `authenticated`
-- (é o comportamento por omissão do Supabase). Bastaria alguém
-- acrescentar uma política permissiva no futuro para abrir a porta.
-- Revogar o privilégio fecha-a ao nível do Postgres, independentemente
-- das políticas que venham a existir.
-- ============================================================

revoke insert, update, delete, truncate on public.boosts from anon, authenticated;
revoke insert, update, delete, truncate on public.boost_packages from anon, authenticated;

-- A verificação de empresas também não é do cliente: ninguém se
-- auto-verifica nem se retira de suspenso.
revoke update on public.companies from anon;

-- Impede que um membro altere o estado de verificação da sua empresa
-- através do UPDATE que lhe é permitido.
create or replace function public.travar_verificacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.verification is distinct from old.verification then
    raise exception 'verificacao_reservada_a_administracao' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_travar_verificacao on public.companies;
create trigger trg_travar_verificacao
  before update on public.companies
  for each row execute function public.travar_verificacao();

revoke all on function public.travar_verificacao() from public, anon, authenticated;
