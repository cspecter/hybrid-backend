-- Fill in addresses from the OCM register where it can vouch for the match.
--
-- 531 feed-created locations have no street address. 322 are New York and 209 are New
-- Jersey, which has no licence register at all — so the register can only ever reach
-- the New York half, and within it only the stores whose names line up.
--
-- WHY THE EARLIER MATCH MISSED THESE. Resolution required two shared name words
-- against the register. The register writes "Treehouse Cannabis"; the tokeniser strips
-- "cannabis" as an industry word, leaving one. The feed writes "Treehouse - Nyack".
-- One shared word, rejected — while the register held the address all along:
-- 28 Route 59, Nyack.
--
-- The corroboration that makes one shared word safe here is the locality the feed puts
-- after the dash. "Treehouse - Nyack" against a register row in Nyack is a different
-- claim from "Treehouse" against a register row anywhere in the state. City is
-- preferred; county is accepted but recorded separately because it is weaker.
--
-- Yield is 40 of 531. Small, and worth doing because it is free and authoritative —
-- these addresses come from the state, not from a guess. The remaining 491 need a
-- geocoder.
create or replace function public.feed_enrich_addresses_from_register()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_n integer;
begin
  with tgt as (
    select l.id,
           btrim(split_part(l.name, ' - ', 1)) as name_part,
           nullif(btrim(substring(l.name from position(' - ' in l.name)+3)), '') as locality
    from public.locations l
    where l.status = 'draft' and l.address_line1 is null
  ),
  best as (
    select distinct on (t.id)
           t.id, o.license_number, o.address_line_1, o.zip_code, o.business_website,
           public.ocm_norm(t.locality) = public.ocm_norm(o.city) as city_hit
    from tgt t
    join public.ny_ocm_licenses o
      on public.ocm_tokens(t.name_part) && o.clean_name_tokens
     and o.license_status = 'Active' and o.operational_status = 'Active'
     and nullif(btrim(coalesce(o.address_line_1, '')), '') is not null
    where t.locality is null
       or public.ocm_norm(t.locality) = public.ocm_norm(o.city)
       or public.ocm_norm(t.locality) = public.ocm_norm(o.county)
    order by t.id,
             array_length(public.ocm_overlap(public.ocm_tokens(t.name_part), o.clean_name_tokens), 1) desc,
             (public.ocm_norm(t.locality) = public.ocm_norm(o.city)) desc
  )
  update public.locations l
     set address_line1       = b.address_line_1,
         postal_code_id      = coalesce(l.postal_code_id,
                                 (select pc.id from public.postal_codes pc
                                   where pc.postal_code = left(b.zip_code, 5)
                                     and pc.country_code = 'US' order by pc.id limit 1)),
         ocm_license_number  = coalesce(l.ocm_license_number, b.license_number),
         website             = coalesce(l.website, nullif(btrim(coalesce(b.business_website,'')), '')),
         description         = coalesce(l.description, '') || ' Address from the NY OCM register ('
                               || case when b.city_hit then 'name + city' else 'name + county' end || ').',
         updated_at          = now()
    from best b
   where l.id = b.id and l.address_line1 is null;
  get diagnostics v_n = row_count;

  return jsonb_build_object('addresses_filled', v_n,
    'still_without_address', (select count(*) from public.locations
                               where status='draft' and address_line1 is null));
end;
$$;

revoke all on function public.feed_enrich_addresses_from_register() from public, anon, authenticated;
