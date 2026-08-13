-- ============================================================
-- Rate limiting por IP para chamadas sem sessão iniciada.
-- A anon key é pública, por isso sem isto qualquer pessoa
-- poderia esgotar os créditos do modelo.
--
-- O IP é dado pessoal (RGPD): guardado só para conter abuso,
-- nunca legível por utilizadores, e apagado ao fim de 24 h.
-- ============================================================
alter table public.ai_queries
  add column if not exists client_ip text;

comment on column public.ai_queries.client_ip is
  'Só para rate limiting de chamadas sem sessão. Apagado após 24 h. Nunca exposto a utilizadores.';

-- índice parcial: só interessa a janela recente dos anónimos
create index if not exists idx_ai_ip_janela
  on public.ai_queries(client_ip, created_at desc)
  where client_ip is not null;

-- Minimização de dados: limpar IPs com mais de 24 h.
create or replace function public.ai_purge_ips()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.ai_queries
     set client_ip = null
   where client_ip is not null
     and created_at < now() - interval '24 hours';
$$;

revoke all on function public.ai_purge_ips() from public, anon, authenticated;
grant execute on function public.ai_purge_ips() to service_role;
