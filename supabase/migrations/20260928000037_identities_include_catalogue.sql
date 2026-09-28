-- Fold catalogue matching into the one maintenance call, for every brand that has a list.
-- Line names are relearned first, because they come out of the catalogue and the matching
-- depends on them.
create or replace function public.refresh_product_identities() returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_pending integer;
  v_tokens  integer;
  v_lines   integer;
  v_cat     integer := 0;
  v_matched integer := 0;
  v_merges  integer;
  v_retire  jsonb;
  b record;
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
  v_cat    := refresh_brand_catalogue_norm();
  v_lines  := refresh_brand_line_terms();

  for b in select distinct brand_key from brand_catalogue loop
    v_matched := v_matched + match_brand_catalogue(b.brand_key);
  end loop;

  v_merges := build_identity_merges();
  v_retire := retire_duplicate_products();

  return jsonb_build_object(
    'tokens', v_tokens,
    'catalogue_skus', v_cat,
    'line_terms', v_lines,
    'catalogue_matches', v_matched,
    'merges', v_merges,
    'merges_by_reason', (select jsonb_object_agg(reason, n) from
       (select reason, count(*) as n from product_identity_merge group by reason) z),
    'retirement', v_retire,
    'identities', (select count(distinct canonical_key) from v_identity_resolved));
end $$;

comment on function public.refresh_product_identities() is
  'One call to bring identities up to date: token stats, catalogue normalisation, line names, catalogue matching for every brand with a list, the merge rules, and the duplicate retirement.';

revoke all on function public.refresh_product_identities() from anon, authenticated;
