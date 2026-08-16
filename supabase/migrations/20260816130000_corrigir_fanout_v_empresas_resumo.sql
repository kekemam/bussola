-- ============================================================
-- Correção: a vista somava o gasto multiplicado pelo número de anúncios.
--
-- A versão anterior juntava companies -> listings -> boosts na mesma
-- consulta. Com 3 anúncios e 1 destaque de 15€, o produto cartesiano
-- gerava 3 linhas do mesmo destaque e o sum() dava 45€.
--
-- count(distinct ...) escondia o problema nas contagens, mas sum() não
-- tem equivalente seguro: sum(distinct) colapsaria dois destaques do
-- mesmo valor. A solução é agregar cada tabela em separado.
-- ============================================================
create or replace view public.v_empresas_resumo
with (security_invoker = true) as
select
  c.id, c.name, c.category, c.city, c.verification, c.created_at,
  coalesce(l.publicados, 0)   as anuncios_publicados,
  coalesce(b.ativos, 0)       as destaques_ativos,
  coalesce(b.gasto_cents, 0)  as gasto_cents
from public.companies c
left join lateral (
  select count(*) as publicados
    from public.listings x
   where x.company_id = c.id and x.status = 'published'
) l on true
left join lateral (
  select count(*) filter (where y.status = 'active' and y.ends_at > now()) as ativos,
         sum(y.price_cents) filter (where y.status in ('active','expired')) as gasto_cents
    from public.boosts y
   where y.company_id = c.id
) b on true
order by c.created_at desc;
