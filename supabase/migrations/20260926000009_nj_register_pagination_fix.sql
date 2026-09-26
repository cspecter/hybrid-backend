-- Percent-encode the pagination token properly.
--
-- The CRC map's nextToken is not an opaque id — it is raw JSON:
--
--   {"markerMapId":"8bed33fa-...","id":"0a5f7345-..."}
--
-- Pasting that into a query string after swapping only '+' and '&' left the braces,
-- quotes, colons and commas unescaped, and the API answered HTTP 400. Page one worked,
-- so the failure only appeared at 250 rows.
--
-- A general encoder rather than another round of guessing which characters matter:
-- everything outside the RFC 3986 unreserved set becomes %XX, byte by byte, so this is
-- correct for any token shape the endpoint adopts later.
create or replace function public.url_encode(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(
    case when ch ~ '^[A-Za-z0-9_.~-]$' then ch
         else (select string_agg('%' || upper(h[1]), '')
                 from regexp_matches(encode(convert_to(ch, 'UTF8'), 'hex'), '..', 'g') h)
    end, '' order by ord), '')
  from regexp_split_to_table(coalesce(p_text, ''), '') with ordinality t(ch, ord)
$$;

revoke all on function public.url_encode(text) from public, anon, authenticated;

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
  v_status integer; v_body text; v_page jsonb;
  v_all    jsonb := '[]'::jsonb;
  v_token  text; v_pages integer := 0; v_stored integer;
begin
  loop
    select status, content into v_status, v_body from extensions.http_get(v_url);
    if v_status is distinct from 200 then
      raise exception 'nj_register_sync: HTTP % from the CRC map on page %', v_status, v_pages + 1;
    end if;
    v_page := v_body::jsonb;
    v_all  := v_all || coalesce(v_page->'markers', '[]'::jsonb);
    v_token := v_page->>'nextToken';
    v_pages := v_pages + 1;
    exit when v_token is null or v_pages >= 10;
    v_url := c_base || '?nextToken=' || public.url_encode(v_token);
  end loop;

  if jsonb_array_length(v_all) = 0 then
    raise exception 'nj_register_sync: no markers returned — keeping the existing mirror';
  end if;

  delete from public.nj_dispensary_register;

  insert into public.nj_dispensary_register
    (external_id, name, formatted_address, street, city, state, postal_code,
     latitude, longitude, website, tags, name_tokens)
  select e->>'id', e->>'name', e->>'formattedAddress',
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
  return jsonb_build_object('pages', v_pages, 'markers_fetched', jsonb_array_length(v_all), 'stored', v_stored);
end;
$$;

revoke all on function public.nj_register_sync() from public, anon, authenticated;
