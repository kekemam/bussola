-- ============================================================
-- Funções de destaque
-- ============================================================

-- Destaque em vigor para um anúncio (o que termina mais tarde).
create or replace function public.destaque_ativo(p_listing uuid)
returns table (ends_at timestamptz, dias_restantes int, package_id text)
language sql
stable
security invoker
set search_path = ''
as $$
  select b.ends_at,
         ceil(extract(epoch from (b.ends_at - now()))/86400)::int,
         b.package_id
  from public.boosts b
  where b.listing_id = p_listing
    and b.status = 'active'
    and b.ends_at > now()
  order by b.ends_at desc
  limit 1;
$$;

-- Compra de destaque. Só o service_role a pode chamar: a Edge Function
-- confirma o pagamento e só depois grava. Prolongar soma ao tempo que
-- ainda falta, em vez de o substituir.
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
  select * into v_pack from public.boost_packages
   where id = p_package and active;
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

  return v_row;
end;
$$;

-- Marca como expirados os destaques cujo período terminou.
create or replace function public.expirar_destaques()
returns int
language sql
security definer
set search_path = ''
as $$
  with x as (
    update public.boosts set status = 'expired'
     where status = 'active' and ends_at <= now()
    returning 1
  ) select count(*)::int from x;
$$;

-- Nenhuma destas é chamável pelo cliente.
revoke all on function public.comprar_destaque(uuid, text, text) from public, anon, authenticated;
revoke all on function public.expirar_destaques() from public, anon, authenticated;
grant execute on function public.comprar_destaque(uuid, text, text) to service_role;
grant execute on function public.expirar_destaques() to service_role;

-- Esta é de leitura e pode ser usada pelo frontend.
grant execute on function public.destaque_ativo(uuid) to anon, authenticated, service_role;
