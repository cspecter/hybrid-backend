-- Indexes
-- Database indexes for performance optimization
-- Updated: Uses profiles, locations, and new table/column names

-- =====================================
-- UNIQUE CONSTRAINT INDEXES
-- =====================================

CREATE UNIQUE INDEX featured_items_item_id_type_unique_idx ON public.featured_items USING btree (item_id, item_type);

CREATE UNIQUE INDEX follow_ids_idx ON public.relationships USING btree (followee_id, follower_id);

CREATE UNIQUE INDEX giveaway_entry_idx ON public.giveaway_entries USING btree (profile_id, giveaway_id);

CREATE UNIQUE INDEX idx_lists_products_unique_list_product ON public.lists_products USING btree (list_id, product_id);

CREATE UNIQUE INDEX idx_stash_product_profile ON public.stash USING btree (product_id, profile_id);

CREATE UNIQUE INDEX posts_products_post_id_product_id_idx ON public.posts_products USING btree (post_id, product_id);

CREATE UNIQUE INDEX product_feature_plus_types_idx ON public.product_features USING btree (name, type_id);

CREATE UNIQUE INDEX product_feature_type_name_idx ON public.product_feature_types USING btree (name);

CREATE UNIQUE INDEX related_products_product_id_related_id_idx ON public.related_products USING btree (product_id, related_product_id);

CREATE UNIQUE INDEX products_states_product_id_state_id_idx ON public.products_states USING btree (product_id, state_id);

CREATE UNIQUE INDEX stash_profile_product_idx ON public.stash USING btree (profile_id, product_id);

-- =====================================
-- LOCATIONS INDEXES
-- =====================================

CREATE INDEX locations_address_trgm_idx ON public.locations USING gin (address_line1 extensions.gin_trgm_ops);

CREATE INDEX locations_fts_idx ON public.locations USING gin (fts);

CREATE INDEX locations_coordinates_idx ON public.locations USING gist (coordinates);

CREATE INDEX locations_name_trgm_idx ON public.locations USING gin (name extensions.gin_trgm_ops);

CREATE INDEX locations_brand_id_idx ON public.locations USING btree (brand_id);

CREATE INDEX locations_location_type_idx ON public.locations USING btree (location_type);

-- JSONB features index for fast feature queries
CREATE INDEX locations_features_idx ON public.locations USING gin (features);

-- =====================================
-- FEATURED ITEMS INDEXES
-- =====================================

CREATE INDEX featured_items_type_order_idx ON public.featured_items USING btree (item_type, sort_order);

-- =====================================
-- GIVEAWAYS INDEXES
-- =====================================

CREATE INDEX giveaways_description_trgm_idx ON public.giveaways USING gin (description extensions.gin_trgm_ops);

CREATE INDEX giveaways_fts_idx ON public.giveaways USING gin (fts);

CREATE INDEX giveaways_name_trgm_idx ON public.giveaways USING gin (name extensions.gin_trgm_ops);

-- =====================================
-- LISTS INDEXES
-- =====================================

CREATE INDEX lists_description_trgm_idx ON public.lists USING gin (description extensions.gin_trgm_ops);

CREATE INDEX lists_fts_idx ON public.lists USING gin (fts);

CREATE INDEX lists_name_trgm_idx ON public.lists USING gin (name extensions.gin_trgm_ops);

CREATE INDEX lists_profile_id_idx ON public.lists USING btree (profile_id);

-- =====================================
-- POSTAL CODES INDEXES
-- =====================================

CREATE INDEX postal_code_idx ON public.postal_codes USING btree (postal_code);

CREATE INDEX postal_code_location_idx ON public.postal_codes USING btree (latitude, longitude);

CREATE INDEX postal_codes_geom_idx ON public.postal_codes USING gist (geom);

-- =====================================
-- POSTS INDEXES
-- =====================================

CREATE INDEX posts_fts_idx ON public.posts USING gin (fts);

CREATE INDEX posts_message_trgm_idx ON public.posts USING gin (message extensions.gin_trgm_ops);

CREATE INDEX posts_profile_id_idx ON public.posts USING btree (profile_id);

-- =====================================
-- PRODUCT CATEGORIES INDEXES
-- =====================================

CREATE INDEX product_categories_fts ON public.product_categories USING gin (fts);

CREATE INDEX product_category_name_idx ON public.product_categories USING btree (name);

-- =====================================
-- PRODUCTS INDEXES
-- =====================================

CREATE INDEX products_cached_brand_names_idx ON public.products USING btree (cached_brand_names);

CREATE INDEX products_category_id_idx ON public.products USING btree (category_id);

CREATE INDEX products_fts ON public.products USING gin (fts);

CREATE INDEX products_fts_idx ON public.products USING gin (fts);

CREATE INDEX products_name_idx ON public.products USING btree (name);

CREATE INDEX products_name_trgm_idx ON public.products USING gin (name extensions.gin_trgm_ops);

CREATE INDEX products_slug ON public.products USING btree (slug);

CREATE INDEX release_date_products_idx ON public.products USING btree (release_date);

-- =====================================
-- PRODUCT VARIANTS INDEXES
-- =====================================

CREATE UNIQUE INDEX product_variants_sku_idx ON public.product_variants USING btree (sku);

CREATE INDEX product_variants_product_id_idx ON public.product_variants USING btree (product_id);

CREATE INDEX product_variants_is_active_idx ON public.product_variants USING btree (is_active) WHERE is_active = true;

CREATE INDEX product_variants_attributes_idx ON public.product_variants USING gin (attributes);

-- =====================================
-- PRODUCT BRANDS INDEXES
-- =====================================

CREATE INDEX idx_product_brands_product_id ON public.product_brands USING btree (product_id);

CREATE INDEX idx_product_brands_brand_id ON public.product_brands USING btree (brand_id);

CREATE UNIQUE INDEX product_brands_unique_idx ON public.product_brands USING btree (product_id, brand_id);

-- =====================================
-- RELATED PRODUCTS INDEXES
-- =====================================

CREATE INDEX related_products_product_id_idx ON public.related_products USING btree (product_id);

-- =====================================
-- RELATIONSHIPS INDEXES
-- =====================================

CREATE INDEX relationships_followee_id ON public.relationships USING btree (followee_id);

CREATE INDEX relationships_follower_id ON public.relationships USING btree (follower_id);

-- =====================================
-- STASH INDEXES
-- =====================================

CREATE INDEX stash_product_id_idx ON public.stash USING btree (product_id);

CREATE INDEX stash_profile_id_idx ON public.stash USING btree (profile_id);

-- =====================================
-- PROFILES INDEXES
-- =====================================

CREATE INDEX profiles_fts_idx ON public.profiles USING gin (fts);

CREATE INDEX profiles_display_name ON public.profiles USING btree (display_name);

CREATE INDEX profiles_display_name_trgm_idx ON public.profiles USING gin (display_name extensions.gin_trgm_ops);

CREATE INDEX profiles_role_id_idx ON public.profiles USING btree (role_id);

CREATE INDEX profiles_slug ON public.profiles USING btree (slug);

CREATE INDEX profiles_username_trgm_idx ON public.profiles USING gin (username extensions.gin_trgm_ops);

CREATE UNIQUE INDEX profiles_auth_id_idx ON public.profiles USING btree (auth_id);

-- =====================================
-- US LOCATIONS INDEXES
-- =====================================

CREATE INDEX us_locations_zip_code ON public.us_locations USING btree (zip_code);

-- =====================================
-- NOTIFICATIONS INDEXES
-- =====================================

CREATE INDEX notifications_profile_id_idx ON public.notifications USING btree (profile_id);

CREATE INDEX notifications_unread_idx ON public.notifications USING btree (profile_id, is_read) WHERE is_read = false;

CREATE INDEX notifications_created_at_idx ON public.notifications USING btree (created_at DESC);

CREATE INDEX notification_preferences_profile_id_idx ON public.notification_preferences USING btree (profile_id);

CREATE INDEX push_tokens_profile_id_idx ON public.push_tokens USING btree (profile_id);

CREATE INDEX push_queue_status_idx ON public.push_queue USING btree (status) WHERE status = 'pending';

CREATE INDEX push_queue_send_at_idx ON public.push_queue USING btree (send_at) WHERE status = 'pending';
