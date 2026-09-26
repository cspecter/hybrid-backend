-- New Jersey does have an authoritative dispensary list after all.
--
-- Everything built so far assumed New Jersey publishes nothing machine-readable: its
-- open-data entry is a bare link, and the CRC's permit pages are individual PDFs with
-- no addresses. That is true of the pages I checked, and it is why 209 New Jersey
-- locations were created with a name and nothing else.
--
-- It was not true of the CRC's own "Find a Dispensary" map. The map is rendered by
-- Atlist, a third-party embed, and its marker data — the state's list, published by
-- the state, on a public page with no authentication — carries exactly what was
-- missing: name, full formatted address, latitude, longitude and website, for 329
-- dispensaries.
--
--   source  nj.gov/cannabis/dispensaries/find  ->  api.atlist.com/v1/map/<id>/markers
--
-- Same shape as the NY OCM sync: fetch, validate, replace wholesale inside one
-- transaction, refuse an empty response rather than wiping the mirror. Paged, because
-- the endpoint returns 250 at a time behind a nextToken.

create table if not exists public.nj_dispensary_register (
  id                bigserial primary key,
  external_id       text,
  name              text not null,
  formatted_address text,
  street            text,
  city              text,
  state             text,
  postal_code       text,
  latitude          double precision,
  longitude         double precision,
  website           text,
  tags              text,
  name_tokens       text[],
  synced_at         timestamptz not null default now()
);

create index if not exists nj_register_name_tokens_idx on public.nj_dispensary_register using gin (name_tokens);
create index if not exists nj_register_city_idx        on public.nj_dispensary_register (lower(city));

comment on table public.nj_dispensary_register is
  'Mirror of the NJ CRC Find-a-Dispensary map (nj.gov -> api.atlist.com). Replaced wholesale by nj_register_sync().';

create or replace function public.nj_register_sync()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  c_base constant text := 'https://api.atlist.com/v1/map/8bed33fa-9b8c-4c51-bb33-74cd0d98628a/markers';
  v_url    text := c_base;
  v_status integer;
  v_body   text;
  v_page   jsonb;
  v_all    jsonb := '[]'::jsonb;
  v_token  text;
  v_pages  integer := 0;
  v_stored integer;
begin
  loop
    select status, content into v_status, v_body from extensions.http_get(v_url);
    if v_status is distinct from 200 then
      raise exception 'nj_register_sync: HTTP % from the CRC map', v_status;
    end if;
    v_page := v_body::jsonb;
    v_all  := v_all || coalesce(v_page->'markers', '[]'::jsonb);
    v_token := v_page->>'nextToken';
    v_pages := v_pages + 1;
    exit when v_token is null or v_pages >= 10;   -- 10 pages of 250 is ample headroom
    v_url := c_base || '?nextToken=' || replace(replace(v_token, '+', '%2B'), '&', '%26');
  end loop;

  -- An empty answer is far likelier to be an upstream fault than a state with no
  -- dispensaries. Refuse rather than replace good rows with none.
  if jsonb_array_length(v_all) = 0 then
    raise exception 'nj_register_sync: no markers returned — keeping the existing mirror';
  end if;

  delete from public.nj_dispensary_register;

  insert into public.nj_dispensary_register
    (external_id, name, formatted_address, street, city, state, postal_code,
     latitude, longitude, website, tags, name_tokens)
  select e->>'id',
         e->>'name',
         e->>'formattedAddress',
         -- "460 Maple Ave, Elizabeth, NJ 07202, USA" splits cleanly on commas.
         btrim(split_part(e->>'formattedAddress', ',', 1)),
         btrim(split_part(e->>'formattedAddress', ',', 2)),
         btrim(split_part(btrim(split_part(e->>'formattedAddress', ',', 3)), ' ', 1)),
         nullif(btrim(split_part(btrim(split_part(e->>'formattedAddress', ',', 3)), ' ', 2)), ''),
         (e->>'lat')::double precision,
         (e->>'long')::double precision,
         nullif(btrim(coalesce(e->>'buttonLink','')), ''),
         (select string_agg(x, '|') from jsonb_array_elements_text(coalesce(e->'tags','[]'::jsonb)) x),
         public.ocm_tokens(e->>'name')
  from jsonb_array_elements(v_all) e
  where nullif(btrim(coalesce(e->>'name','')), '') is not null;

  get diagnostics v_stored = row_count;
  return jsonb_build_object('pages', v_pages, 'markers_fetched', jsonb_array_length(v_all),
                            'stored', v_stored);
end;
$$;

revoke all on function public.nj_register_sync() from public, anon, authenticated;
revoke all on table public.nj_dispensary_register from anon, authenticated;
alter table public.nj_dispensary_register enable row level security;
