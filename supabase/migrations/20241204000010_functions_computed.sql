-- Computed Column Functions for GraphQL
-- These functions are used by pg_graphql to expose computed columns
-- Updated: Uses profiles instead of users, locations instead of dispensary_locations
-- Removed: cannabis_strains computed columns

-- =====================================
-- DEALS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct p.display_name) from deals_locations left join locations l on l.id = location_id left join profiles p on p.id = l.brand_id where deal_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_brand_names"("rec" "public"."deals") IS '@graphql({"name": "s_brand_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct pc.place_name) from deals_locations left join locations l on l.id = location_id left join postal_codes pc on pc.id = l.postal_code_id where deal_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_cities"("rec" "public"."deals") IS '@graphql({"name": "s_cities"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.created_at);
$$;

COMMENT ON FUNCTION "public"."_ts_deals_date_created"("rec" "public"."deals") IS '@graphql({"name": "s_dateCreated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.updated_at);
$$;

COMMENT ON FUNCTION "public"."_ts_deals_date_updated"("rec" "public"."deals") IS '@graphql({"name": "s_dateUpdated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.expiration_date);
$$;

COMMENT ON FUNCTION "public"."_ts_deals_expirationdate"("rec" "public"."deals") IS '@graphql({"name": "s_expirationDate"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_id"("rec" "public"."deals") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(json_build_array(extensions.st_x(l.coordinates::extensions.geometry), extensions.st_y(l.coordinates::extensions.geometry))) from deals_locations left join locations l on l.id = location_id where deal_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_latlng"("rec" "public"."deals") IS '@graphql({"name": "s_latlng"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct l.name) from deals_locations left join locations l on l.id = location_id where deal_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_location_names"("rec" "public"."deals") IS '@graphql({"name": "s_location_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct pc.postal_code) from deals_locations left join locations l on l.id = location_id left join postal_codes pc on pc.id = l.postal_code_id where deal_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_postal_codes"("rec" "public"."deals") IS '@graphql({"name": "s_postal_codes"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.name from products p left join product_categories pc on pc.id = category_id where p.id = rec.product_id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_product_category"("rec" "public"."deals") IS '@graphql({"name": "s_product_category"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from products where id = rec.product_id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_product_name"("rec" "public"."deals") IS '@graphql({"name": "s_product_name"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.release_date);
$$;

COMMENT ON FUNCTION "public"."_ts_deals_releasedate"("rec" "public"."deals") IS '@graphql({"name": "s_releaseDate"})';

CREATE OR REPLACE FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_agg(distinct pc.state) from deals_locations left join locations l on l.id = location_id left join postal_codes pc on pc.id = l.postal_code_id where deal_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_deals_states"("rec" "public"."deals") IS '@graphql({"name": "s_states"})';

-- =====================================
-- LOCATIONS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_locations_brand_name"("rec" "public"."locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select display_name from profiles where id = rec.brand_id;
$$;

COMMENT ON FUNCTION "public"."_ts_locations_brand_name"("rec" "public"."locations") IS '@graphql({"name": "s_brand_name"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_city"("rec" "public"."locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.place_name from postal_codes pc where pc.id = rec.postal_code_id;
$$;

COMMENT ON FUNCTION "public"."_ts_locations_city"("rec" "public"."locations") IS '@graphql({"name": "s_city"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_date_created"("rec" "public"."locations") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.created_at);
$$;

COMMENT ON FUNCTION "public"."_ts_locations_date_created"("rec" "public"."locations") IS '@graphql({"name": "s_dateCreated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_date_updated"("rec" "public"."locations") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.updated_at);
$$;

COMMENT ON FUNCTION "public"."_ts_locations_date_updated"("rec" "public"."locations") IS '@graphql({"name": "s_dateUpdated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_employees"("rec" "public"."locations") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(profile_id) from location_employees where location_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_locations_employees"("rec" "public"."locations") IS '@graphql({"name": "s_employees"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_id"("rec" "public"."locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_locations_id"("rec" "public"."locations") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_latlng"("rec" "public"."locations") RETURNS "json"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select json_build_array(extensions.st_x(rec.coordinates::extensions.geometry), extensions.st_y(rec.coordinates::extensions.geometry));
$$;

COMMENT ON FUNCTION "public"."_ts_locations_latlng"("rec" "public"."locations") IS '@graphql({"name": "s_latlng"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_postal_code"("rec" "public"."locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.postal_code from postal_codes pc where pc.id = rec.postal_code_id;
$$;

COMMENT ON FUNCTION "public"."_ts_locations_postal_code"("rec" "public"."locations") IS '@graphql({"name": "s_postal_code"})';

CREATE OR REPLACE FUNCTION "public"."_ts_locations_state"("rec" "public"."locations") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.state from postal_codes pc where pc.id = rec.postal_code_id;
$$;

COMMENT ON FUNCTION "public"."_ts_locations_state"("rec" "public"."locations") IS '@graphql({"name": "s_state"})';

-- =====================================
-- GIVEAWAYS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.display_name) from product_brands left join profiles p on p.id = brand_id where product_id = rec.product_id;
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_brand_names"("rec" "public"."giveaways") IS '@graphql({"name": "s_brand_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.created_at);
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_date_created"("rec" "public"."giveaways") IS '@graphql({"name": "s_dateCreated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.updated_at);
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_date_updated"("rec" "public"."giveaways") IS '@graphql({"name": "s_dateUpdated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.end_time);
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_end_time"("rec" "public"."giveaways") IS '@graphql({"name": "s_endTime"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_id"("rec" "public"."giveaways") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select coalesce(array_agg(pc.postal_code), '{"00000"}'::text[]) from giveaways_regions g left join region_postal_codes rpc on rpc.region_id = g.region_id left join postal_codes pc on pc.id = rpc.postal_code_id where g.giveaway_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_postal_codes"("rec" "public"."giveaways") IS '@graphql({"name": "s_postal_codes"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select pc.name from products p left join product_categories pc on pc.id = category_id where p.id = rec.product_id;
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_product_categories"("rec" "public"."giveaways") IS '@graphql({"name": "s_product_category"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select name from products where id = rec.product_id;
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_product_name"("rec" "public"."giveaways") IS '@graphql({"name": "s_product_name"})';

CREATE OR REPLACE FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.start_time);
$$;

COMMENT ON FUNCTION "public"."_ts_giveaways_start_time"("rec" "public"."giveaways") IS '@graphql({"name": "s_startTime"})';

-- =====================================
-- LISTS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select display_name from profiles where profiles.id = rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_display_name"("rec" "public"."lists") IS '@graphql({"name": "s_display_name"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_id"("rec" "public"."lists") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.name) from lists_products left join products p on p.id = product_id left join product_categories pc on pc.id = p.category_id where list_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_product_categories"("rec" "public"."lists") IS '@graphql({"name": "s_product_categories"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.id) from lists_products left join products p on p.id = product_id left join product_categories pc on pc.id = p.category_id where list_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_product_category_ids"("rec" "public"."lists") IS '@graphql({"name": "s_product_category_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(product_id) from lists_products where list_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_product_ids"("rec" "public"."lists") IS '@graphql({"name": "s_product_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.name) from lists_products left join products p on p.id = product_id where list_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_product_names"("rec" "public"."lists") IS '@graphql({"name": "s_product_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_profile_id"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_profile_id"("rec" "public"."lists") IS '@graphql({"name": "s_profile_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select username from profiles where profiles.id = rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_ts_lists_username"("rec" "public"."lists") IS '@graphql({"name": "s_username"})';

-- =====================================
-- POSTAL CODES COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_postal_codes_id"("rec" "public"."postal_codes") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array[rec.latitude, rec.latitude];
$$;

COMMENT ON FUNCTION "public"."_ts_postal_codes_latlng"("rec" "public"."postal_codes") IS '@graphql({"name": "s_latlng"})';

-- =====================================
-- POSTS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select place_name from postal_codes where id = rec.postal_code_id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_city"("rec" "public"."posts") IS '@graphql({"name": "s_city"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.created_at);
$$;

COMMENT ON FUNCTION "public"."_ts_posts_date_created"("rec" "public"."posts") IS '@graphql({"name": "s_dateCreated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.updated_at);
$$;

COMMENT ON FUNCTION "public"."_ts_posts_date_updated"("rec" "public"."posts") IS '@graphql({"name": "s_dateUpdated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select display_name from profiles where profiles.id = rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_display_name"("rec" "public"."posts") IS '@graphql({"name": "s_display_name"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_id"("rec" "public"."posts") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(list_id) from posts_lists where post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_list_ids"("rec" "public"."posts") IS '@graphql({"name": "s_list_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(l.name) from posts_lists left join lists l on l.id = list_id where post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_list_names"("rec" "public"."posts") IS '@graphql({"name": "s_list_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array[latitude, longitude] from postal_codes where id = rec.postal_code_id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_location"("rec" "public"."posts") IS '@graphql({"name": "s_latlng"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.name) from posts_products pp left join products p on p.id = pp.product_id left join product_categories pc on pc.id = p.category_id where pp.post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_product_categories"("rec" "public"."posts") IS '@graphql({"name": "s_product_categories"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(Distinct pc.id) from posts_products pp left join products p on p.id = pp.product_id left join product_categories pc on pc.id = p.category_id where pp.post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_product_category_ids"("rec" "public"."posts") IS '@graphql({"name": "s_product_category_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(pp.product_id) from posts_products pp where pp.post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_product_ids"("rec" "public"."posts") IS '@graphql({"name": "s_product_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.name) from posts_products pp left join products p on p.id = pp.product_id where pp.post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_product_names"("rec" "public"."posts") IS '@graphql({"name": "s_product_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select state from postal_codes where id = rec.postal_code_id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_region"("rec" "public"."posts") IS '@graphql({"name": "s_region"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(distinct pt.tag) from posts_hashtags left join post_tags pt on pt.id = post_tag_id where post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_tags"("rec" "public"."posts") IS '@graphql({"name": "s_tags"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_profile_id"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_profile_id"("rec" "public"."posts") IS '@graphql({"name": "s_profile_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_profile_ids"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(profile_id) from posts_profiles where post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_profile_ids"("rec" "public"."posts") IS '@graphql({"name": "s_profile_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_profile_names"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.display_name) from posts_profiles left join profiles p on p.id = profile_id where post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_profile_names"("rec" "public"."posts") IS '@graphql({"name": "s_profile_names"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_profile_usernames"("rec" "public"."posts") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.username) from posts_profiles left join profiles p on p.id = profile_id where post_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_profile_usernames"("rec" "public"."posts") IS '@graphql({"name": "s_profile_usernames"})';

CREATE OR REPLACE FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select username from profiles where profiles.id = rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_ts_posts_username"("rec" "public"."posts") IS '@graphql({"name": "s_username"})';

-- =====================================
-- PRODUCT CATEGORIES COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_product_categories_id"("rec" "public"."product_categories") IS '@graphql({"name": "_id"})';

-- =====================================
-- PRODUCTS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_products_brand"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(p.display_name) from product_brands left join profiles p on p.id = brand_id where product_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_brand"("rec" "public"."products") IS '@graphql({"name": "s_brand"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(brand_id) from product_brands where product_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_brand_ids"("rec" "public"."products") IS '@graphql({"name": "s_brand_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_category"("rec" "public"."products") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select coalesce(id::text, '__NULL__') from product_categories where id = rec.category_id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_category"("rec" "public"."products") IS '@graphql({"name": "s_product_category_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.created_at);
$$;

COMMENT ON FUNCTION "public"."_ts_products_date_created"("rec" "public"."products") IS '@graphql({"name": "s_dateCreated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.updated_at);
$$;

COMMENT ON FUNCTION "public"."_ts_products_date_updated"("rec" "public"."products") IS '@graphql({"name": "s_dateUpdated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_features"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(f.name) from products_product_features left join product_features f on f.id = product_feature_id where product_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_features"("rec" "public"."products") IS '@graphql({"name": "s_features"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_id"("rec" "public"."products") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_id"("rec" "public"."products") IS '@graphql({"name": "_id"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.release_date);
$$;

COMMENT ON FUNCTION "public"."_ts_products_releasedate"("rec" "public"."products") IS '@graphql({"name": "s_releaseDate"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(pa.id) from related_products left join products pa on pa.id = related_product_id where product_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_sub_product_ids"("rec" "public"."products") IS '@graphql({"name": "s_sub_product_ids"})';

CREATE OR REPLACE FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select array_agg(pa.name) from related_products left join products pa on pa.id = related_product_id where product_id = rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_products_sub_products"("rec" "public"."products") IS '@graphql({"name": "s_sub_products"})';

-- =====================================
-- PROFILES COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_ts_profiles_date_created"("rec" "public"."profiles") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.created_at);
$$;

COMMENT ON FUNCTION "public"."_ts_profiles_date_created"("rec" "public"."profiles") IS '@graphql({"name": "s_dateCreated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_profiles_date_updated"("rec" "public"."profiles") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select EXTRACT (EPOCH FROM rec.updated_at);
$$;

COMMENT ON FUNCTION "public"."_ts_profiles_date_updated"("rec" "public"."profiles") IS '@graphql({"name": "s_dateUpdated"})';

CREATE OR REPLACE FUNCTION "public"."_ts_profiles_id"("rec" "public"."profiles") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select rec.id;
$$;

COMMENT ON FUNCTION "public"."_ts_profiles_id"("rec" "public"."profiles") IS '@graphql({"name": "_id"})';

-- =====================================
-- NOTIFICATIONS COMPUTED COLUMNS
-- =====================================

CREATE OR REPLACE FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
    select count(id) from notifications where is_read = false and profile_id = rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") IS '@graphql({"name": "unreadNotificationCount"})';
