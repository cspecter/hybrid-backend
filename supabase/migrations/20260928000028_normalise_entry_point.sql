-- One call to bring the identities up to date after new products land.
--
-- refresh_product_norm only looks at products it has not seen, so the loop is cheap on a
-- steady catalogue. It stays a loop with a batch limit because the whole-catalogue pass
-- runs past the query API's statement timeout.
--
--   select refresh_product_norm(15000);   -- repeat until it returns 0
--   select refresh_product_identities();  -- then this
--
-- Newly promoted products show as duplicates in the app until this has run. That is the
-- trade for not filtering on every app open.
create or replace function public.refresh_product_identities() returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_pending integer;
  v_tokens  integer;
  v_merges  integer;
  v_retire  jsonb;
begin
  select count(*) into v_pending
  from products p
  left join product_categories c on c.id = p.category_id
  where coalesce(c.name, '') not in ('Accessories', 'Experiences')
    and not exists (select 1 from product_norm pn where pn.product_id = p.id);

  if v_pending > 0 then
    return jsonb_build_object(
      'error', 'products still unnormalised',
      'pending', v_pending,
      'hint', 'call refresh_product_norm(15000) until it returns 0, then call this again');
  end if;

  v_tokens := refresh_product_token_stats();
  v_merges := build_identity_merges();
  v_retire := retire_duplicate_products();

  return jsonb_build_object(
    'tokens', v_tokens,
    'sizeless_merges', v_merges,
    'retirement', v_retire,
    'identities', (select count(distinct canonical_key) from v_identity_resolved));
end $$;

comment on function public.refresh_product_identities() is
  'Rebuild token stats, the sizeless merges and the duplicate retirement in one call. Refuses to run while any product is unnormalised, because a missing product cannot be recognised as a duplicate and would be left live.';

revoke all on function public.refresh_product_identities() from anon, authenticated;
