-- Fill New Jersey addresses from the CRC register.
--
-- Same rule the New York reconciliation settled on — two shared name words, or one
-- that is the whole of one side's name — with the locality after the dash used as
-- corroboration where the feed supplies one. New Jersey's register carries
-- coordinates as well as a street address, so these rows land map-ready, which the
-- New York ones do not.
create or replace function public.feed_enrich_addresses_from_nj_register()
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
           t.id, r.street, r.postal_code, r.city, r.latitude, r.longitude, r.website,
           array_length(public.ocm_overlap(public.ocm_tokens(t.name_part), r.name_tokens), 1) as shared,
           public.ocm_norm(t.locality) = public.ocm_norm(r.city) as city_hit
    from tgt t
    join public.nj_dispensary_register r
      on public.ocm_tokens(t.name_part) && r.name_tokens
     and nullif(btrim(coalesce(r.street, '')), '') is not null
    where
      -- two shared words stands on its own
      array_length(public.ocm_overlap(public.ocm_tokens(t.name_part), r.name_tokens), 1) >= 2
      -- one word needs either to be the whole of a name, or the town to agree
      or (array_length(public.ocm_overlap(public.ocm_tokens(t.name_part), r.name_tokens), 1) = 1
          and (array_length(public.ocm_tokens(t.name_part), 1) = 1
            or array_length(r.name_tokens, 1) = 1
            or public.ocm_norm(t.locality) = public.ocm_norm(r.city)))
    order by t.id,
             array_length(public.ocm_overlap(public.ocm_tokens(t.name_part), r.name_tokens), 1) desc,
             (public.ocm_norm(t.locality) = public.ocm_norm(r.city)) desc
  )
  update public.locations l
     set address_line1  = b.street,
         postal_code_id = coalesce(l.postal_code_id,
                            (select pc.id from public.postal_codes pc
                              where pc.postal_code = left(b.postal_code, 5)
                                and pc.country_code = 'US' order by pc.id limit 1)),
         website        = coalesce(l.website, b.website),
         description    = coalesce(l.description, '') || ' Address from the NJ CRC dispensary map ('
                          || case when b.city_hit then 'name + town' else 'name' end || ').',
         updated_at     = now()
    from best b
   where l.id = b.id and l.address_line1 is null;
  get diagnostics v_n = row_count;

  return jsonb_build_object('addresses_filled', v_n,
    'still_without_address', (select count(*) from public.locations
                               where status='draft' and address_line1 is null));
end;
$$;

revoke all on function public.feed_enrich_addresses_from_nj_register() from public, anon, authenticated;
