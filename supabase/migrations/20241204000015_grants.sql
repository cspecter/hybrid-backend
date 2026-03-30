-- Grants and Permissions
-- Schema access grants and table/sequence/function permissions
-- Updated: Uses profiles, locations, and new table names

-- =====================================
-- SCHEMA GRANTS
-- =====================================

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

-- =====================================
-- REALTIME PUBLICATION
-- =====================================

ALTER PUBLICATION supabase_realtime OWNER TO postgres;
ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.notifications;

-- =====================================
-- DEFAULT PRIVILEGES
-- =====================================

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;

-- =====================================
-- TABLE GRANTS - Core Tables
-- =====================================

GRANT ALL ON TABLE public.analytics_posts TO anon;
GRANT ALL ON TABLE public.analytics_posts TO authenticated;
GRANT ALL ON TABLE public.analytics_posts TO service_role;

GRANT ALL ON TABLE public.cloud_files TO anon;
GRANT ALL ON TABLE public.cloud_files TO authenticated;
GRANT ALL ON TABLE public.cloud_files TO service_role;

GRANT ALL ON TABLE public.deal_claims TO anon;
GRANT ALL ON TABLE public.deal_claims TO authenticated;
GRANT ALL ON TABLE public.deal_claims TO service_role;

GRANT ALL ON TABLE public.deals TO anon;
GRANT ALL ON TABLE public.deals TO authenticated;
GRANT ALL ON TABLE public.deals TO service_role;

GRANT ALL ON TABLE public.deals_locations TO anon;
GRANT ALL ON TABLE public.deals_locations TO authenticated;
GRANT ALL ON TABLE public.deals_locations TO service_role;

GRANT ALL ON TABLE public.location_employees TO anon;
GRANT ALL ON TABLE public.location_employees TO authenticated;
GRANT ALL ON TABLE public.location_employees TO service_role;

GRANT ALL ON TABLE public.locations TO anon;
GRANT ALL ON TABLE public.locations TO authenticated;
GRANT ALL ON TABLE public.locations TO service_role;

GRANT ALL ON TABLE public.locations_cloud_files TO anon;
GRANT ALL ON TABLE public.locations_cloud_files TO authenticated;
GRANT ALL ON TABLE public.locations_cloud_files TO service_role;

GRANT ALL ON TABLE public.location_stashlists TO anon;
GRANT ALL ON TABLE public.location_stashlists TO authenticated;
GRANT ALL ON TABLE public.location_stashlists TO service_role;

GRANT ALL ON TABLE public.explore TO anon;
GRANT ALL ON TABLE public.explore TO authenticated;
GRANT ALL ON TABLE public.explore TO service_role;

GRANT ALL ON TABLE public.explore_locations TO anon;
GRANT ALL ON TABLE public.explore_locations TO authenticated;
GRANT ALL ON TABLE public.explore_locations TO service_role;

GRANT ALL ON TABLE public.explore_lists TO anon;
GRANT ALL ON TABLE public.explore_lists TO authenticated;
GRANT ALL ON TABLE public.explore_lists TO service_role;

GRANT ALL ON TABLE public.explore_page TO anon;
GRANT ALL ON TABLE public.explore_page TO authenticated;
GRANT ALL ON TABLE public.explore_page TO service_role;

GRANT ALL ON TABLE public.explore_page_sections TO anon;
GRANT ALL ON TABLE public.explore_page_sections TO authenticated;
GRANT ALL ON TABLE public.explore_page_sections TO service_role;

GRANT ALL ON TABLE public.explore_posts TO anon;
GRANT ALL ON TABLE public.explore_posts TO authenticated;
GRANT ALL ON TABLE public.explore_posts TO service_role;

GRANT ALL ON TABLE public.explore_products TO anon;
GRANT ALL ON TABLE public.explore_products TO authenticated;
GRANT ALL ON TABLE public.explore_products TO service_role;

GRANT ALL ON TABLE public.explore_trending TO anon;
GRANT ALL ON TABLE public.explore_trending TO authenticated;
GRANT ALL ON TABLE public.explore_trending TO service_role;

GRANT ALL ON TABLE public.explore_profiles TO anon;
GRANT ALL ON TABLE public.explore_profiles TO authenticated;
GRANT ALL ON TABLE public.explore_profiles TO service_role;

GRANT ALL ON TABLE public.favorite_locations TO anon;
GRANT ALL ON TABLE public.favorite_locations TO authenticated;
GRANT ALL ON TABLE public.favorite_locations TO service_role;

GRANT ALL ON TABLE public.featured_items TO anon;
GRANT ALL ON TABLE public.featured_items TO authenticated;
GRANT ALL ON TABLE public.featured_items TO service_role;

GRANT ALL ON TABLE public.giveaway_entries TO anon;
GRANT ALL ON TABLE public.giveaway_entries TO authenticated;
GRANT ALL ON TABLE public.giveaway_entries TO service_role;

GRANT ALL ON TABLE public.giveaway_entries_messages TO anon;
GRANT ALL ON TABLE public.giveaway_entries_messages TO authenticated;
GRANT ALL ON TABLE public.giveaway_entries_messages TO service_role;

GRANT ALL ON TABLE public.giveaways TO anon;
GRANT ALL ON TABLE public.giveaways TO authenticated;
GRANT ALL ON TABLE public.giveaways TO service_role;

GRANT ALL ON TABLE public.giveaways_regions TO anon;
GRANT ALL ON TABLE public.giveaways_regions TO authenticated;
GRANT ALL ON TABLE public.giveaways_regions TO service_role;

GRANT ALL ON TABLE public.likes TO anon;
GRANT ALL ON TABLE public.likes TO authenticated;
GRANT ALL ON TABLE public.likes TO service_role;

GRANT ALL ON TABLE public.lists TO anon;
GRANT ALL ON TABLE public.lists TO authenticated;
GRANT ALL ON TABLE public.lists TO service_role;

GRANT ALL ON TABLE public.lists_products TO anon;
GRANT ALL ON TABLE public.lists_products TO authenticated;
GRANT ALL ON TABLE public.lists_products TO service_role;

GRANT ALL ON TABLE public.notification_types TO anon;
GRANT ALL ON TABLE public.notification_types TO authenticated;
GRANT ALL ON TABLE public.notification_types TO service_role;

GRANT ALL ON TABLE public.notification_preferences TO anon;
GRANT ALL ON TABLE public.notification_preferences TO authenticated;
GRANT ALL ON TABLE public.notification_preferences TO service_role;

GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;

GRANT ALL ON TABLE public.push_tokens TO anon;
GRANT ALL ON TABLE public.push_tokens TO authenticated;
GRANT ALL ON TABLE public.push_tokens TO service_role;

GRANT ALL ON TABLE public.push_queue TO anon;
GRANT ALL ON TABLE public.push_queue TO authenticated;
GRANT ALL ON TABLE public.push_queue TO service_role;

GRANT ALL ON TABLE public.post_flags TO anon;
GRANT ALL ON TABLE public.post_flags TO authenticated;
GRANT ALL ON TABLE public.post_flags TO service_role;

GRANT ALL ON TABLE public.post_log TO anon;
GRANT ALL ON TABLE public.post_log TO authenticated;
GRANT ALL ON TABLE public.post_log TO service_role;

GRANT ALL ON TABLE public.post_tags TO anon;
GRANT ALL ON TABLE public.post_tags TO authenticated;
GRANT ALL ON TABLE public.post_tags TO service_role;

GRANT ALL ON TABLE public.postal_codes TO anon;
GRANT ALL ON TABLE public.postal_codes TO authenticated;
GRANT ALL ON TABLE public.postal_codes TO service_role;

GRANT ALL ON TABLE public.posts TO anon;
GRANT ALL ON TABLE public.posts TO authenticated;
GRANT ALL ON TABLE public.posts TO service_role;

GRANT ALL ON TABLE public.posts_hashtags TO anon;
GRANT ALL ON TABLE public.posts_hashtags TO authenticated;
GRANT ALL ON TABLE public.posts_hashtags TO service_role;

GRANT ALL ON TABLE public.posts_lists TO anon;
GRANT ALL ON TABLE public.posts_lists TO authenticated;
GRANT ALL ON TABLE public.posts_lists TO service_role;

GRANT ALL ON TABLE public.posts_products TO anon;
GRANT ALL ON TABLE public.posts_products TO authenticated;
GRANT ALL ON TABLE public.posts_products TO service_role;

GRANT ALL ON TABLE public.posts_profiles TO anon;
GRANT ALL ON TABLE public.posts_profiles TO authenticated;
GRANT ALL ON TABLE public.posts_profiles TO service_role;

GRANT ALL ON TABLE public.product_categories TO anon;
GRANT ALL ON TABLE public.product_categories TO authenticated;
GRANT ALL ON TABLE public.product_categories TO service_role;

GRANT ALL ON TABLE public.product_feature_types TO anon;
GRANT ALL ON TABLE public.product_feature_types TO authenticated;
GRANT ALL ON TABLE public.product_feature_types TO service_role;

GRANT ALL ON TABLE public.product_features TO anon;
GRANT ALL ON TABLE public.product_features TO authenticated;
GRANT ALL ON TABLE public.product_features TO service_role;

GRANT ALL ON TABLE public.products TO anon;
GRANT ALL ON TABLE public.products TO authenticated;
GRANT ALL ON TABLE public.products TO service_role;

GRANT ALL ON TABLE public.product_brands TO anon;
GRANT ALL ON TABLE public.product_brands TO authenticated;
GRANT ALL ON TABLE public.product_brands TO service_role;

GRANT ALL ON TABLE public.product_variants TO anon;
GRANT ALL ON TABLE public.product_variants TO authenticated;
GRANT ALL ON TABLE public.product_variants TO service_role;

GRANT ALL ON TABLE public.products_cloud_files TO anon;
GRANT ALL ON TABLE public.products_cloud_files TO authenticated;
GRANT ALL ON TABLE public.products_cloud_files TO service_role;

GRANT ALL ON TABLE public.products_product_features TO anon;
GRANT ALL ON TABLE public.products_product_features TO authenticated;
GRANT ALL ON TABLE public.products_product_features TO service_role;

GRANT ALL ON TABLE public.related_products TO anon;
GRANT ALL ON TABLE public.related_products TO authenticated;
GRANT ALL ON TABLE public.related_products TO service_role;

GRANT ALL ON TABLE public.products_states TO anon;
GRANT ALL ON TABLE public.products_states TO authenticated;
GRANT ALL ON TABLE public.products_states TO service_role;

GRANT ALL ON TABLE public.region_postal_codes TO anon;
GRANT ALL ON TABLE public.region_postal_codes TO authenticated;
GRANT ALL ON TABLE public.region_postal_codes TO service_role;

GRANT ALL ON TABLE public.regions TO anon;
GRANT ALL ON TABLE public.regions TO authenticated;
GRANT ALL ON TABLE public.regions TO service_role;

GRANT ALL ON TABLE public.relationships TO anon;
GRANT ALL ON TABLE public.relationships TO authenticated;
GRANT ALL ON TABLE public.relationships TO service_role;

GRANT ALL ON TABLE public.roles TO anon;
GRANT ALL ON TABLE public.roles TO authenticated;
GRANT ALL ON TABLE public.roles TO service_role;

GRANT ALL ON TABLE public.shop_now TO anon;
GRANT ALL ON TABLE public.shop_now TO authenticated;
GRANT ALL ON TABLE public.shop_now TO service_role;

GRANT ALL ON TABLE public.stash TO anon;
GRANT ALL ON TABLE public.stash TO authenticated;
GRANT ALL ON TABLE public.stash TO service_role;

GRANT ALL ON TABLE public.states TO anon;
GRANT ALL ON TABLE public.states TO authenticated;
GRANT ALL ON TABLE public.states TO service_role;

GRANT ALL ON TABLE public.subscriptions_lists TO anon;
GRANT ALL ON TABLE public.subscriptions_lists TO authenticated;
GRANT ALL ON TABLE public.subscriptions_lists TO service_role;

GRANT ALL ON TABLE public.us_locations TO anon;
GRANT ALL ON TABLE public.us_locations TO authenticated;
GRANT ALL ON TABLE public.us_locations TO service_role;

GRANT ALL ON TABLE public.profile_blocks TO anon;
GRANT ALL ON TABLE public.profile_blocks TO authenticated;
GRANT ALL ON TABLE public.profile_blocks TO service_role;

GRANT ALL ON TABLE public.profile_admins TO anon;
GRANT ALL ON TABLE public.profile_admins TO authenticated;
GRANT ALL ON TABLE public.profile_admins TO service_role;

GRANT ALL ON TABLE public.profile_delete_requests TO anon;
GRANT ALL ON TABLE public.profile_delete_requests TO authenticated;
GRANT ALL ON TABLE public.profile_delete_requests TO service_role;

GRANT ALL ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;

-- =====================================
-- TABLE GRANTS - Directus Tables
-- =====================================

GRANT ALL ON TABLE public.directus_activity TO authenticated;
GRANT ALL ON TABLE public.directus_activity TO service_role;

GRANT ALL ON TABLE public.directus_collections TO authenticated;
GRANT ALL ON TABLE public.directus_collections TO service_role;

GRANT ALL ON TABLE public.directus_dashboards TO authenticated;
GRANT ALL ON TABLE public.directus_dashboards TO service_role;

GRANT ALL ON TABLE public.directus_fields TO authenticated;
GRANT ALL ON TABLE public.directus_fields TO service_role;

GRANT ALL ON TABLE public.directus_files TO authenticated;
GRANT ALL ON TABLE public.directus_files TO service_role;

GRANT ALL ON TABLE public.directus_flows TO anon;
GRANT ALL ON TABLE public.directus_flows TO authenticated;
GRANT ALL ON TABLE public.directus_flows TO service_role;

GRANT ALL ON TABLE public.directus_folders TO authenticated;
GRANT ALL ON TABLE public.directus_folders TO service_role;

GRANT ALL ON TABLE public.directus_migrations TO authenticated;
GRANT ALL ON TABLE public.directus_migrations TO service_role;

GRANT ALL ON TABLE public.directus_notifications TO authenticated;
GRANT ALL ON TABLE public.directus_notifications TO service_role;

GRANT ALL ON TABLE public.directus_operations TO anon;
GRANT ALL ON TABLE public.directus_operations TO authenticated;
GRANT ALL ON TABLE public.directus_operations TO service_role;

GRANT ALL ON TABLE public.directus_panels TO authenticated;
GRANT ALL ON TABLE public.directus_panels TO service_role;

GRANT ALL ON TABLE public.directus_permissions TO authenticated;
GRANT ALL ON TABLE public.directus_permissions TO service_role;

GRANT ALL ON TABLE public.directus_presets TO authenticated;
GRANT ALL ON TABLE public.directus_presets TO service_role;

GRANT ALL ON TABLE public.directus_relations TO authenticated;
GRANT ALL ON TABLE public.directus_relations TO service_role;

GRANT ALL ON TABLE public.directus_revisions TO authenticated;
GRANT ALL ON TABLE public.directus_revisions TO service_role;

GRANT ALL ON TABLE public.directus_roles TO authenticated;
GRANT ALL ON TABLE public.directus_roles TO service_role;

GRANT ALL ON TABLE public.directus_sessions TO authenticated;
GRANT ALL ON TABLE public.directus_sessions TO service_role;

GRANT ALL ON TABLE public.directus_settings TO authenticated;
GRANT ALL ON TABLE public.directus_settings TO service_role;

GRANT ALL ON TABLE public.directus_shares TO authenticated;
GRANT ALL ON TABLE public.directus_shares TO service_role;

GRANT ALL ON TABLE public.directus_translations TO anon;
GRANT ALL ON TABLE public.directus_translations TO authenticated;
GRANT ALL ON TABLE public.directus_translations TO service_role;

GRANT ALL ON TABLE public.directus_users TO authenticated;
GRANT ALL ON TABLE public.directus_users TO service_role;

GRANT ALL ON TABLE public.directus_versions TO anon;
GRANT ALL ON TABLE public.directus_versions TO authenticated;
GRANT ALL ON TABLE public.directus_versions TO service_role;

GRANT ALL ON TABLE public.directus_webhooks TO authenticated;
GRANT ALL ON TABLE public.directus_webhooks TO service_role;

-- =====================================
-- SEQUENCE GRANTS
-- =====================================

GRANT ALL ON SEQUENCE public.analytics_posts_id_seq TO anon;
GRANT ALL ON SEQUENCE public.analytics_posts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.analytics_posts_id_seq TO service_role;



GRANT ALL ON SEQUENCE public.deals_locations_id_seq TO anon;
GRANT ALL ON SEQUENCE public.deals_locations_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.deals_locations_id_seq TO service_role;











GRANT ALL ON SEQUENCE public.location_employees_id_seq TO anon;
GRANT ALL ON SEQUENCE public.location_employees_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.location_employees_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.locations_cloud_files_id_seq TO anon;
GRANT ALL ON SEQUENCE public.locations_cloud_files_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.locations_cloud_files_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_locations_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_locations_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_locations_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_lists_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_lists_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_lists_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_page_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_page_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_page_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_page_sections_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_page_sections_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_page_sections_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_posts_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_posts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_posts_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_products_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_products_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_products_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_trending_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_trending_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_trending_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.explore_profiles_id_seq TO anon;
GRANT ALL ON SEQUENCE public.explore_profiles_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.explore_profiles_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.favorite_locations_id_seq TO anon;
GRANT ALL ON SEQUENCE public.favorite_locations_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.favorite_locations_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.featured_items_id_seq TO anon;
GRANT ALL ON SEQUENCE public.featured_items_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.featured_items_id_seq TO service_role;



GRANT ALL ON SEQUENCE public.giveaways_regions_id_seq TO anon;
GRANT ALL ON SEQUENCE public.giveaways_regions_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.giveaways_regions_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.likes_id_seq TO anon;
GRANT ALL ON SEQUENCE public.likes_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.likes_id_seq TO service_role;


GRANT ALL ON SEQUENCE public.lists_products_id_seq TO anon;
GRANT ALL ON SEQUENCE public.lists_products_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.lists_products_id_seq TO service_role;



GRANT ALL ON SEQUENCE public.post_flags_id_seq TO anon;
GRANT ALL ON SEQUENCE public.post_flags_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.post_flags_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.post_log_id_seq TO anon;
GRANT ALL ON SEQUENCE public.post_log_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.post_log_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.post_tags_id_seq TO anon;
GRANT ALL ON SEQUENCE public.post_tags_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.post_tags_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.postal_codes_id_seq TO anon;
GRANT ALL ON SEQUENCE public.postal_codes_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.postal_codes_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.posts_hashtags_id_seq TO anon;
GRANT ALL ON SEQUENCE public.posts_hashtags_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.posts_hashtags_id_seq TO service_role;


GRANT ALL ON SEQUENCE public.posts_lists_id_seq TO anon;
GRANT ALL ON SEQUENCE public.posts_lists_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.posts_lists_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.posts_products_id_seq TO anon;
GRANT ALL ON SEQUENCE public.posts_products_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.posts_products_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.posts_profiles_id_seq TO anon;
GRANT ALL ON SEQUENCE public.posts_profiles_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.posts_profiles_id_seq TO service_role;


GRANT ALL ON SEQUENCE public.product_feature_types_id_seq TO anon;
GRANT ALL ON SEQUENCE public.product_feature_types_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.product_feature_types_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.product_features_id_seq TO anon;
GRANT ALL ON SEQUENCE public.product_features_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.product_features_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.product_brands_id_seq TO anon;
GRANT ALL ON SEQUENCE public.product_brands_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.product_brands_id_seq TO service_role;


GRANT ALL ON SEQUENCE public.products_cloud_files_id_seq TO anon;
GRANT ALL ON SEQUENCE public.products_cloud_files_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.products_cloud_files_id_seq TO service_role;


GRANT ALL ON SEQUENCE public.products_product_features_id_seq TO anon;
GRANT ALL ON SEQUENCE public.products_product_features_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.products_product_features_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.related_products_id_seq TO anon;
GRANT ALL ON SEQUENCE public.related_products_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.related_products_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.products_states_id_seq TO anon;
GRANT ALL ON SEQUENCE public.products_states_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.products_states_id_seq TO service_role;


GRANT ALL ON SEQUENCE public.region_postal_codes_id_seq TO anon;
GRANT ALL ON SEQUENCE public.region_postal_codes_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.region_postal_codes_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.regions_id_seq TO anon;
GRANT ALL ON SEQUENCE public.regions_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.regions_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.relationships_id_seq TO anon;
GRANT ALL ON SEQUENCE public.relationships_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.relationships_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.roles_id_seq TO anon;
GRANT ALL ON SEQUENCE public.roles_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.roles_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.stash_id_seq TO anon;
GRANT ALL ON SEQUENCE public.stash_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.stash_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.states_id_seq TO anon;
GRANT ALL ON SEQUENCE public.states_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.states_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.subscriptions_lists_id_seq TO anon;
GRANT ALL ON SEQUENCE public.subscriptions_lists_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.subscriptions_lists_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.us_locations_id_seq TO anon;
GRANT ALL ON SEQUENCE public.us_locations_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.us_locations_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.profile_blocks_id_seq TO anon;
GRANT ALL ON SEQUENCE public.profile_blocks_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.profile_blocks_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.profile_admins_id_seq TO anon;
GRANT ALL ON SEQUENCE public.profile_admins_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.profile_admins_id_seq TO service_role;

GRANT ALL ON SEQUENCE public.profile_delete_requests_id_seq TO anon;
GRANT ALL ON SEQUENCE public.profile_delete_requests_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.profile_delete_requests_id_seq TO service_role;
