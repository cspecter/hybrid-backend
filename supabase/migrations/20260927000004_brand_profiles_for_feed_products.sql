-- Give the promoted products real brand pages.
--
-- cached_brand_names is a cache the trigger maintains from product_brands, and
-- product_brands.brand_id references profiles — so in this app a brand is an account.
-- That is why the 4,609 promoted products landed brandless, and the fix is to create
-- the accounts.
--
-- SCOPE: the 375 brands that have a live product, not the 5,319 in the feed. A brand
-- page with nothing on it is worse than no page, and the other ~4,900 can be created
-- the moment one of their products is promoted. 81 of the 375 already have a brand
-- profile and are simply linked; 294 are new.
--
-- WHAT THESE ACCOUNTS ARE, deliberately: unclaimed placeholders. auth_id is null, so
-- nobody can sign in as one — which is the whole point, because the real owner should
-- be able to claim it later the way stores claim their pages. They take the default
-- role (10), not an elevated one, and are not marked verified: nobody at these brands
-- has confirmed anything yet, and a verified badge on an auto-created page would be a
-- claim we cannot support.

-- ─── The accounts ────────────────────────────────────────────────────────────
with wanted as (
  -- Case-insensitive, because the handle hashes the lowercased name: "Golden Garden"
  -- and "GOLDEN GARDEN" are one brand and must not race for the same username. The
  -- commonest spelling across products wins the display name.
  select mode() within group (order by p.attributes->>'brand') as brand
  from public.products p
  where p.source = 'litalerts' and p.attributes->>'brand' is not null
  group by lower(btrim(p.attributes->>'brand'))
),
missing as (
  select w.brand,
         -- Usernames are unique table-wide, so the slug carries a short hash of the
         -- brand name. Deterministic, so re-running this produces the same handle
         -- rather than a second account for the same brand.
         left(regexp_replace(lower(w.brand), '[^a-z0-9]+', '', 'g'), 22)
           || substr(md5(lower(btrim(w.brand))), 1, 6) as handle
  from wanted w
  where not exists (
    select 1 from public.profiles pr
     where pr.profile_type = 'brand'
       and lower(btrim(pr.display_name)) = lower(btrim(w.brand)))
)
insert into public.profiles (display_name, username, profile_type, status, is_verified, bio)
select m.brand, m.handle, 'brand', 'active', false,
       'Brand page created automatically from dispensary menu data. Unclaimed.'
from missing m
where nullif(btrim(m.handle), '') is not null
  and not exists (select 1 from public.profiles x where x.username = m.handle);

-- ─── The links ───────────────────────────────────────────────────────────────
-- is_primary because each product has exactly one brand here; the table supports
-- several and nothing in the feed distinguishes a secondary one.
insert into public.product_brands (product_id, brand_id, is_primary)
select p.id, pr.id, true
from public.products p
join public.profiles pr
  on pr.profile_type = 'brand'
 and lower(btrim(pr.display_name)) = lower(btrim(p.attributes->>'brand'))
where p.source = 'litalerts'
  and p.attributes->>'brand' is not null
  and not exists (select 1 from public.product_brands pb
                   where pb.product_id = p.id and pb.brand_id = pr.id);
