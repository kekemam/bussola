-- ============================================================
-- Conversas e mensagens
--
-- O painel dizia "conversa aberta" ao aceitar um pedido, mas não havia
-- conversa nenhuma: as mensagens eram um array de exemplo e o que a
-- pessoa escrevesse na app não chegava a lado nenhum.
--
-- A conversa só existe entre um profissional e alguém cujo pedido ele
-- aceitou. É o mesmo critério das avaliações: sem ele, qualquer conta
-- podia escrever a qualquer empresa, e a caixa de entrada de quem
-- atende pessoas em situação vulnerável era o primeiro sítio a encher-se
-- de spam e de burlas.
-- ============================================================
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid references public.consult_requests(id) on delete set null,
  client_name text,                         -- instantâneo, para o lado da empresa
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  unique (company_id, user_id)              -- uma conversa por par
);
comment on table public.conversations is
  'Conversa entre uma empresa e uma pessoa. Só existe com pedido aceite.';

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  -- de que lado veio: calculado no servidor, nunca aceite do cliente
  from_company boolean not null default false,
  body text not null check (length(btrim(body)) between 1 and 4000),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists messages_conversa_idx
  on public.messages (conversation_id, created_at);

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- ---------- Conversas ----------
create policy "ver_as_minhas_conversas" on public.conversations
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or company_id in (select company_id from public.company_members
                       where user_id = (select auth.uid()))
  );

-- Abre qualquer uma das partes, mas só havendo pedido aceite.
create policy "abrir_conversa" on public.conversations
  for insert to authenticated
  with check (
    (
      user_id = (select auth.uid())
      or company_id in (select company_id from public.company_members
                         where user_id = (select auth.uid()))
    )
    and exists (select 1 from public.consult_requests r
                 where r.company_id = conversations.company_id
                   and r.user_id = conversations.user_id
                   and r.status in ('aceite','concluida'))
  );

revoke update, delete on public.conversations from anon, authenticated;

-- ---------- Mensagens ----------
create policy "ver_as_mensagens_da_conversa" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.conversations c
     where c.id = messages.conversation_id
       and (c.user_id = (select auth.uid())
            or c.company_id in (select company_id from public.company_members
                                 where user_id = (select auth.uid())))));

create policy "escrever_na_minha_conversa" on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.conversations c
       where c.id = messages.conversation_id
         and (c.user_id = (select auth.uid())
              or c.company_id in (select company_id from public.company_members
                                   where user_id = (select auth.uid())))));

-- Marcar como lida é a única alteração possível.
create policy "marcar_lida" on public.messages
  for update to authenticated
  using (exists (
    select 1 from public.conversations c
     where c.id = messages.conversation_id
       and (c.user_id = (select auth.uid())
            or c.company_id in (select company_id from public.company_members
                                 where user_id = (select auth.uid())))))
  with check (true);

revoke delete on public.messages from anon, authenticated;

-- De que lado veio a mensagem não pode vir do cliente: bastava enviar
-- from_company=true para uma mensagem se fazer passar pela do advogado.
create or replace function public.carimbar_mensagem()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_empresa uuid;
begin
  select c.company_id into v_empresa
    from public.conversations c where c.id = new.conversation_id;
  new.from_company := exists (
    select 1 from public.company_members m
     where m.company_id = v_empresa and m.user_id = new.sender_id);
  new.read_at := null;
  return new;
end;
$$;
revoke all on function public.carimbar_mensagem() from public, anon, authenticated;

drop trigger if exists carimbar_mensagem on public.messages;
create trigger carimbar_mensagem
  before insert on public.messages
  for each row execute function public.carimbar_mensagem();

-- No update, só `read_at` muda.
create or replace function public.travar_mensagem()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.from_company is distinct from old.from_company
     or new.body is distinct from old.body
     or new.created_at is distinct from old.created_at then
    raise exception 'so_a_leitura_pode_mudar' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.travar_mensagem() from public, anon, authenticated;

drop trigger if exists travar_mensagem on public.messages;
create trigger travar_mensagem
  before update on public.messages
  for each row execute function public.travar_mensagem();

-- Ordenar a lista de conversas pela actividade sem a tornar escrevível.
create or replace function public.tocar_conversa()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversations set last_message_at = new.created_at
   where id = new.conversation_id;
  return null;
end;
$$;
revoke all on function public.tocar_conversa() from public, anon, authenticated;

drop trigger if exists tocar_conversa on public.messages;
create trigger tocar_conversa
  after insert on public.messages
  for each row execute function public.tocar_conversa();
