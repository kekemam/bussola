-- ============================================================
-- Avaliações e agenda
--
-- Duas tabelas que faltavam para o painel do profissional deixar de
-- mostrar exemplos: quem já foi atendido avalia, e o profissional
-- marca as consultas.
--
-- A regra que sustenta tudo: só avalia quem teve pedido aceite. Sem
-- isso, o selo de confiança da plataforma vale o que vale uma caixa de
-- texto aberta — e num sítio onde a escolha do advogado é feita por
-- quem está em situação vulnerável, avaliações falsas fazem dano real.
-- ============================================================

-- ---------- Avaliações ----------
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text check (comment is null or length(btrim(comment)) <= 2000),
  author_name text,           -- instantâneo, como nos pedidos
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id) -- uma avaliação por pessoa e profissional
);
comment on table public.reviews is
  'Avaliações de profissionais. Só escreve quem teve um pedido aceite.';

create index if not exists reviews_empresa_idx on public.reviews (company_id, created_at desc);

alter table public.reviews enable row level security;

-- Leitura pública: as avaliações aparecem no perfil do profissional na app.
create policy "avaliacoes_publicas" on public.reviews
  for select to anon, authenticated using (true);

-- Escreve quem foi atendido, e só sobre quem o atendeu.
create policy "avaliar_quem_me_atendeu" on public.reviews
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.consult_requests r
                 where r.company_id = reviews.company_id
                   and r.user_id = (select auth.uid())
                   and r.status in ('aceite','concluida'))
  );

-- O autor corrige a sua avaliação; a empresa nunca lhe toca.
create policy "corrigir_a_minha_avaliacao" on public.reviews
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke delete on public.reviews from anon, authenticated;

-- Média e contagem no próprio perfil: a app lista profissionais sem
-- sessão e não pode agregar avaliações à mão em cada cartão.
alter table public.companies add column if not exists rating_avg numeric(2,1);
alter table public.companies add column if not exists rating_count int not null default 0;

create or replace function public.recalcular_avaliacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid := coalesce(new.company_id, old.company_id);
begin
  update public.companies c set
    rating_avg = (select round(avg(r.rating)::numeric,1) from public.reviews r where r.company_id = v_id),
    rating_count = (select count(*) from public.reviews r where r.company_id = v_id)
  where c.id = v_id;
  return null;
end;
$$;
revoke all on function public.recalcular_avaliacao() from public, anon, authenticated;

drop trigger if exists recalcular_avaliacao on public.reviews;
create trigger recalcular_avaliacao
  after insert or update or delete on public.reviews
  for each row execute function public.recalcular_avaliacao();

-- ---------- Agenda ----------
create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid references public.consult_requests(id) on delete set null,
  starts_at timestamptz not null,
  duration_min int not null default 45 check (duration_min between 15 and 480),
  mode text not null default 'online' check (mode in ('online','presencial')),
  notes text,
  client_name text,           -- instantâneo, como nos pedidos
  status text not null default 'marcada'
    check (status in ('marcada','realizada','cancelada')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.appointments is
  'Consultas marcadas. Quem marca é o profissional; ambas as partes veem.';

create index if not exists appointments_empresa_idx on public.appointments (company_id, starts_at);
create index if not exists appointments_pessoa_idx on public.appointments (user_id, starts_at);

alter table public.appointments enable row level security;

-- Veem as duas partes.
create policy "ver_as_minhas_consultas" on public.appointments
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or company_id in (select company_id from public.company_members
                       where user_id = (select auth.uid()))
  );

-- Marca o profissional, e só com quem já lhe pediu ajuda: sem esta
-- verificação uma empresa podia encher a agenda de qualquer utilizador
-- cujo id conhecesse.
create policy "empresa_marca" on public.appointments
  for insert to authenticated
  with check (
    company_id in (select company_id from public.company_members
                    where user_id = (select auth.uid()))
    and exists (select 1 from public.consult_requests r
                 where r.company_id = appointments.company_id
                   and r.user_id = appointments.user_id
                   and r.status in ('aceite','concluida'))
  );

create policy "empresa_altera_a_consulta" on public.appointments
  for update to authenticated
  using (company_id in (select company_id from public.company_members
                         where user_id = (select auth.uid())))
  with check (company_id in (select company_id from public.company_members
                              where user_id = (select auth.uid())));

revoke delete on public.appointments from anon, authenticated;
