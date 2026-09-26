-- Load addresses supplied by hand for the locations no register could reach.
--
-- 276 feed-created locations had a name and nothing else: 246 in New York whose names
-- do not line up with the OCM register, and 30 in New Jersey the CRC map missed. They
-- were exported, filled in off-platform, and come back keyed on location_id.
--
-- A function rather than a one-off UPDATE, because this will happen again every time
-- the feed brings stores no register knows. It takes the same shape the export
-- produces and can be re-run with a new batch.
--
-- SAFETY: it only writes where address_line1 is still null, so re-running cannot
-- overwrite an address the registers have since supplied, and a stale copy of the
-- spreadsheet cannot undo newer work.
create or replace function public.locations_apply_supplied_addresses(p_rows jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_updated integer; v_no_zip integer;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'expected a JSON array of {id, a, c, z}';
  end if;

  with incoming as (
    select (e->>'id')::integer as id,
           nullif(btrim(e->>'a'), '') as address_line1,
           nullif(btrim(e->>'c'), '') as city,
           left(nullif(btrim(e->>'z'), ''), 5) as zip
    from jsonb_array_elements(p_rows) e
  )
  update public.locations l
     set address_line1  = i.address_line1,
         postal_code_id = coalesce(l.postal_code_id,
                            (select pc.id from public.postal_codes pc
                              where pc.postal_code = i.zip and pc.country_code = 'US'
                              order by pc.id limit 1)),
         description    = coalesce(l.description, '') || ' Address supplied manually '
                          || to_char(now(), 'YYYY-MM-DD') || '.',
         updated_at     = now()
    from incoming i
   where l.id = i.id
     and l.address_line1 is null          -- never clobber an address already found
     and i.address_line1 is not null;
  get diagnostics v_updated = row_count;

  -- A zip that matches no postal_codes row leaves the location unmappable even though
  -- it now has a street. Counted so it is visible rather than silently incomplete.
  select count(*) into v_no_zip
    from jsonb_array_elements(p_rows) e
    join public.locations l on l.id = (e->>'id')::integer
   where l.postal_code_id is null;

  return jsonb_build_object(
    'addresses_applied', v_updated,
    'supplied', jsonb_array_length(p_rows),
    'still_without_postcode', v_no_zip,
    'locations_without_address_remaining',
      (select count(*) from public.locations where status='draft' and address_line1 is null));
end;
$$;

revoke all on function public.locations_apply_supplied_addresses(jsonb) from public, anon, authenticated;
