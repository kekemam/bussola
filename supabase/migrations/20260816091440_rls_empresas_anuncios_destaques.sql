-- ============================================================
-- RLS do lado do negócio
--
-- Decisão central: a tabela `boosts` NÃO aceita escrita do cliente.
-- Se aceitasse, qualquer empresa podia chamar a API REST diretamente
-- e oferecer-se destaques gratuitos e ilimitados — a única fonte de
-- receita da plataforma. A inserção passa obrigatoriamente por uma
-- função de servidor que confirma o pagamento antes de gravar.
-- ============================================================

alter table public.companies       enable row level security;
alter table public.company_members enable row level security;
alter table public.listings        enable row level security;
alter table public.boost_packages  enable row level security;
alter table public.boosts          enable row level security;

-- ---------- company_members ----------
-- Sem referência a companies, para não criar recursão entre políticas.
create policy "membros_veem_as_suas_ligacoes" on public.company_members
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------- companies ----------
-- Diretório público: qualquer pessoa vê as empresas que não foram
-- rejeitadas nem suspensas.
create policy "empresas_visiveis_ao_publico" on public.companies
  for select to anon, authenticated
  using (verification not in ('rejected','suspended'));

-- Gestão: só quem é membro.
create policy "membros_gerem_a_empresa" on public.companies
  for update to authenticated
  using (id in (select company_id from public.company_members where user_id = (select auth.uid())))
  with check (id in (select company_id from public.company_members where user_id = (select auth.uid())));

-- Registo: qualquer utilizador autenticado pode criar a sua empresa.
-- A verificação começa sempre em 'pending' — ninguém se auto-verifica.
create policy "criar_empresa" on public.companies
  for insert to authenticated
  with check (verification = 'pending');

-- ---------- listings ----------
create policy "anuncios_publicados_sao_publicos" on public.listings
  for select to anon, authenticated
  using (status = 'published');

create policy "empresa_ve_os_seus_anuncios" on public.listings
  for select to authenticated
  using (company_id in (select company_id from public.company_members where user_id = (select auth.uid())));

create policy "empresa_gere_os_seus_anuncios" on public.listings
  for all to authenticated
  using (company_id in (select company_id from public.company_members where user_id = (select auth.uid())))
  with check (company_id in (select company_id from public.company_members where user_id = (select auth.uid())));

-- ---------- boost_packages ----------
-- Preços são informação pública; alterá-los é do servidor.
create policy "precos_publicos" on public.boost_packages
  for select to anon, authenticated
  using (active);

-- ---------- boosts ----------
-- Leitura: a empresa vê o histórico dos seus destaques.
create policy "empresa_ve_os_seus_destaques" on public.boosts
  for select to authenticated
  using (company_id in (select company_id from public.company_members where user_id = (select auth.uid())));

-- Escrita: nenhuma política para anon/authenticated.
-- Sem política, o RLS nega por omissão. Só o service_role escreve,
-- através de comprar_destaque().
