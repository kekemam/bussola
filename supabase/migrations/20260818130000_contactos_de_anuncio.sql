-- ============================================================
-- Contactos sobre anúncios
--
-- O pedido de consulta já tinha tabela própria, mas os outros três
-- papéis não: candidatar-se a uma vaga, contactar sobre um quarto ou
-- inscrever-se num evento não gravavam nada. O "Enviar mensagem" do
-- arrendamento tinha até uma caixa de texto com id que ninguém lia — o
-- mesmo padrão do pedido de consulta antes de ser corrigido.
--
-- Uma tabela só para os três, porque o gesto é o mesmo: alguém
-- responde a um anúncio e a empresa decide. O tipo vem do anúncio,
-- não é escolhido pelo cliente.
-- ============================================================
create table if not exists public.listing_contacts (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (length(btrim(message)) between 5 and 4000),
  -- contexto de quem contacta, no momento em que contactou
  contact_name text,
  contact_city text,
  contact_country text,
  status text not null default 'novo'
    check (status in ('novo','aceite','recusado','concluido')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (listing_id, user_id)   -- um contacto por pessoa e anúncio
);
comment on table public.listing_contacts is
  'Candidaturas a vagas, contactos sobre alojamento e inscrições em eventos.';

create index if not exists listing_contacts_empresa_idx
  on public.listing_contacts (company_id, created_at desc);
create index if not exists listing_contacts_pessoa_idx
  on public.listing_contacts (user_id, created_at desc);

alter table public.listing_contacts enable row level security;

create policy "criar_o_meu_contacto" on public.listing_contacts
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    -- a empresa tem de ser mesmo a dona do anúncio: sem isto o cliente
    -- podia dirigir o contacto a qualquer empresa
    and exists (select 1 from public.listings l
                 where l.id = listing_contacts.listing_id
                   and l.company_id = listing_contacts.company_id)
  );

create policy "ver_os_meus_contactos" on public.listing_contacts
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or company_id in (select company_id from public.company_members
                       where user_id = (select auth.uid()))
  );

create policy "empresa_responde_ao_contacto" on public.listing_contacts
  for update to authenticated
  using (company_id in (select company_id from public.company_members
                         where user_id = (select auth.uid())))
  with check (company_id in (select company_id from public.company_members
                              where user_id = (select auth.uid())));

-- Responder é mudar o estado, como nos pedidos de consulta: a empresa
-- não reescreve o que a pessoa disse nem o nome com que o disse.
create or replace function public.travar_contacto()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.listing_id is distinct from old.listing_id
     or new.company_id is distinct from old.company_id
     or new.user_id is distinct from old.user_id
     or new.message is distinct from old.message
     or new.contact_name is distinct from old.contact_name
     or new.contact_city is distinct from old.contact_city
     or new.contact_country is distinct from old.contact_country
     or new.created_at is distinct from old.created_at then
    raise exception 'so_o_estado_pode_mudar' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.travar_contacto() from public, anon, authenticated;

drop trigger if exists travar_contacto on public.listing_contacts;
create trigger travar_contacto
  before update on public.listing_contacts
  for each row execute function public.travar_contacto();

revoke delete on public.listing_contacts from anon, authenticated;

-- ------------------------------------------------------------
-- A conversa passa a abrir também por um contacto aceite, e não só
-- por um pedido de consulta. A regra em si não muda: só se fala com
-- quem já respondeu ao anúncio e foi aceite.
-- ------------------------------------------------------------
drop policy if exists "abrir_conversa" on public.conversations;
create policy "abrir_conversa" on public.conversations
  for insert to authenticated
  with check (
    (
      user_id = (select auth.uid())
      or company_id in (select company_id from public.company_members
                         where user_id = (select auth.uid()))
    )
    and (
      exists (select 1 from public.consult_requests r
               where r.company_id = conversations.company_id
                 and r.user_id = conversations.user_id
                 and r.status in ('aceite','concluida'))
      or
      exists (select 1 from public.listing_contacts c
               where c.company_id = conversations.company_id
                 and c.user_id = conversations.user_id
                 and c.status in ('aceite','concluido'))
    )
  );
