-- ============================================================
-- O destaque tem de ser visível sem expor quem paga.
--
-- A app precisa de saber que anúncios estão destacados, para os pôr
-- no topo. Mas `boosts` é privada de propósito: quanto uma empresa
-- gastou, e quando, não é da conta de mais ninguém — muito menos da
-- concorrência.
--
-- Solução: o anúncio passa a carregar apenas a data em que o destaque
-- termina. É o mínimo necessário para ordenar, e não revela pacote,
-- preço, histórico nem quantas vezes a empresa comprou.
-- ============================================================
alter table public.listings
  add column if not exists boosted_until timestamptz;

comment on column public.listings.boosted_until is
  'Fim do destaque em vigor. Denormalizado a partir de boosts para o '
  'diretório público poder ordenar sem expor valores nem histórico de compras.';

create index if not exists idx_listings_destaque
  on public.listings(boosted_until desc nulls last)
  where status = 'published';

-- Preencher a partir do que já existe
update public.listings l
   set boosted_until = sub.fim
  from (
    select listing_id, max(ends_at) as fim
      from public.boosts
     where status = 'active' and ends_at > now()
     group by listing_id
  ) sub
 where sub.listing_id = l.id;

-- A compra passa a actualizar o anúncio na mesma transação.
create or replace function public.comprar_destaque(
  p_listing uuid,
  p_package text,
  p_payment_ref text default null
)
returns public.boosts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pack   public.boost_packages%rowtype;
  v_company uuid;
  v_base   timestamptz;
  v_row    public.boosts%rowtype;
begin
  select * into v_pack from public.boost_packages where id = p_package and active;
  if not found then
    raise exception 'pacote_invalido: %', p_package using errcode = '22023';
  end if;

  select company_id into v_company from public.listings where id = p_listing;
  if v_company is null then
    raise exception 'anuncio_inexistente: %', p_listing using errcode = '23503';
  end if;

  -- prolongar: parte do fim do destaque em vigor, se houver
  select greatest(coalesce(max(b.ends_at), now()), now()) into v_base
    from public.boosts b
   where b.listing_id = p_listing and b.status = 'active' and b.ends_at > now();

  insert into public.boosts (listing_id, company_id, package_id, days, price_cents, starts_at, ends_at, payment_ref)
  values (p_listing, v_company, v_pack.id, v_pack.days, v_pack.price_cents,
          now(), v_base + make_interval(days => v_pack.days), p_payment_ref)
  returning * into v_row;

  update public.listings
     set boosted_until = v_row.ends_at
   where id = p_listing;

  return v_row;
end;
$$;
revoke all on function public.comprar_destaque(uuid, text, text) from public, anon, authenticated;
grant execute on function public.comprar_destaque(uuid, text, text) to service_role;

-- A expiração também limpa a marca do anúncio.
create or replace function public.expirar_destaques()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare n int;
begin
  with x as (
    update public.boosts set status = 'expired'
     where status = 'active' and ends_at <= now()
    returning 1
  ) select count(*) into n from x;

  update public.listings
     set boosted_until = null
   where boosted_until is not null and boosted_until <= now();

  return n;
end;
$$;
revoke all on function public.expirar_destaques() from public, anon, authenticated;
grant execute on function public.expirar_destaques() to service_role;
