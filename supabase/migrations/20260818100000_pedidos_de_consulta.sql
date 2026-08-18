-- ============================================================
-- Pedidos de consulta
--
-- O botão "Pedir consulta" na app abria uma caixa de texto, dizia
-- "Pedido enviado" e deitava fora o que a pessoa tinha escrito: o
-- texto nunca era lido e nada chegava ao profissional. Quem estava do
-- outro lado via só dados de demonstração.
--
-- Esta tabela é o que liga os dois lados.
--
-- O nome, a cidade e o país de quem pede ficam gravados na própria
-- linha em vez de serem lidos de `profiles`. Assim o profissional vê
-- o que precisa para responder sem que as empresas ganhem acesso aos
-- perfis dos utilizadores — e o que fica partilhado é o que a pessoa
-- partilhou naquele momento, com aquele profissional.
-- ============================================================
create table if not exists public.consult_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (length(btrim(message)) between 10 and 4000),
  -- contexto de quem pede, no momento em que pediu
  requester_name text,
  requester_city text,
  requester_country text,
  status text not null default 'nova'
    check (status in ('nova','aceite','recusada','concluida')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.consult_requests is
  'Pedidos de consulta enviados a um profissional a partir da app.';

create index if not exists consult_requests_empresa_idx
  on public.consult_requests (company_id, created_at desc);
create index if not exists consult_requests_pessoa_idx
  on public.consult_requests (user_id, created_at desc);

alter table public.consult_requests enable row level security;

-- Quem pede cria o seu próprio pedido, e só o seu.
create policy "criar_o_meu_pedido" on public.consult_requests
  for insert to authenticated
  with check (user_id = (select auth.uid()));

-- Vêem o pedido as duas partes: quem pediu e a empresa destinatária.
create policy "ver_os_meus_pedidos" on public.consult_requests
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or company_id in (select company_id from public.company_members
                       where user_id = (select auth.uid()))
  );

-- Só a empresa responde. O WITH CHECK impede que, ao responder, o
-- pedido seja movido para outra empresa.
create policy "empresa_responde" on public.consult_requests
  for update to authenticated
  using (company_id in (select company_id from public.company_members
                         where user_id = (select auth.uid())))
  with check (company_id in (select company_id from public.company_members
                              where user_id = (select auth.uid())));

-- Responder significa mudar o estado. Sem isto, a política de UPDATE
-- deixava a empresa reescrever o texto do pedido e o nome de quem o
-- fez — ou seja, adulterar o registo de quem lhe pediu ajuda.
create or replace function public.travar_pedido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.company_id is distinct from old.company_id
     or new.user_id is distinct from old.user_id
     or new.message is distinct from old.message
     or new.requester_name is distinct from old.requester_name
     or new.requester_city is distinct from old.requester_city
     or new.requester_country is distinct from old.requester_country
     or new.created_at is distinct from old.created_at then
    raise exception 'so_o_estado_pode_mudar' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.travar_pedido() from public, anon, authenticated;

drop trigger if exists travar_pedido on public.consult_requests;
create trigger travar_pedido
  before update on public.consult_requests
  for each row execute function public.travar_pedido();

-- Ninguém apaga: o histórico do pedido pertence às duas partes. Fecha-se
-- mudando o estado para 'concluida'.
revoke delete on public.consult_requests from anon, authenticated;
