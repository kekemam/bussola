-- ============================================================
-- Vistas para a consola.
-- Agregar no Postgres e não no navegador: o cliente não deve
-- descarregar todas as compras só para somar uma coluna.
--
-- security_invoker garante que as vistas respeitam o RLS de quem
-- consulta — sem isto correriam com os privilégios do dono e
-- furariam as políticas.
-- ============================================================

create or replace view public.v_receita_destaques
with (security_invoker = true) as
select
  date_trunc('month', b.created_at)::date as mes,
  count(*)                                as compras,
  sum(b.price_cents)                      as receita_cents,
  round(avg(b.price_cents))::int          as media_cents
from public.boosts b
where b.status in ('active','expired')
group by 1
order by 1 desc;

create or replace view public.v_pacotes_vendidos
with (security_invoker = true) as
select
  p.id, p.name, p.days, p.price_cents,
  count(b.id)                              as vendidos,
  coalesce(sum(b.price_cents),0)           as receita_cents
from public.boost_packages p
left join public.boosts b
  on b.package_id = p.id and b.status in ('active','expired')
group by p.id, p.name, p.days, p.price_cents, p.sort
order by p.sort;

create or replace view public.v_empresas_resumo
with (security_invoker = true) as
select
  c.id, c.name, c.category, c.city, c.verification, c.created_at,
  count(distinct l.id) filter (where l.status = 'published') as anuncios_publicados,
  count(distinct b.id) filter (where b.status = 'active' and b.ends_at > now()) as destaques_ativos,
  coalesce(sum(b.price_cents) filter (where b.status in ('active','expired')),0) as gasto_cents
from public.companies c
left join public.listings l on l.company_id = c.id
left join public.boosts   b on b.company_id = c.id
group by c.id, c.name, c.category, c.city, c.verification, c.created_at
order by c.created_at desc;

grant select on public.v_receita_destaques, public.v_pacotes_vendidos, public.v_empresas_resumo
  to authenticated, service_role;
