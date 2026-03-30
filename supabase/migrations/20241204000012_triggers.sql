-- Triggers
-- Database triggers that call functions on data changes
-- Updated: Uses profiles, locations, and unified timestamp triggers

-- =====================================
-- AUTH USER SYNC TRIGGER
-- =====================================

CREATE TRIGGER trg_create_or_update_public_profile 
    AFTER INSERT OR DELETE OR UPDATE ON auth.users 
    FOR EACH ROW EXECUTE FUNCTION public.fn_insert_update_or_delete_public_profile_from_auth();

-- =====================================
-- FULL-TEXT SEARCH UPDATE TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER locations_fts_update 
    BEFORE INSERT OR UPDATE ON public.locations 
    FOR EACH ROW EXECUTE FUNCTION public.update_locations_fts();

CREATE OR REPLACE TRIGGER giveaways_fts_update 
    BEFORE INSERT OR UPDATE ON public.giveaways 
    FOR EACH ROW EXECUTE FUNCTION public.update_giveaways_fts();

CREATE OR REPLACE TRIGGER lists_fts_update 
    BEFORE INSERT OR UPDATE ON public.lists 
    FOR EACH ROW EXECUTE FUNCTION public.update_lists_fts();

CREATE OR REPLACE TRIGGER posts_fts_update 
    BEFORE INSERT OR UPDATE ON public.posts 
    FOR EACH ROW EXECUTE FUNCTION public.update_posts_fts();

CREATE OR REPLACE TRIGGER products_fts_update 
    BEFORE INSERT OR UPDATE ON public.products 
    FOR EACH ROW EXECUTE FUNCTION public.update_products_fts();

CREATE OR REPLACE TRIGGER profiles_fts_update 
    BEFORE INSERT OR UPDATE ON public.profiles 
    FOR EACH ROW EXECUTE FUNCTION public.update_profiles_fts();

-- =====================================
-- FTS CASCADE UPDATE TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER product_categories_cascade_fts_update 
    AFTER UPDATE ON public.product_categories 
    FOR EACH ROW EXECUTE FUNCTION public.cascade_product_category_fts_update();

CREATE OR REPLACE TRIGGER products_cascade_fts_update 
    AFTER UPDATE ON public.products 
    FOR EACH ROW EXECUTE FUNCTION public.cascade_product_fts_update();

CREATE OR REPLACE TRIGGER profiles_cascade_fts_update 
    AFTER UPDATE ON public.profiles 
    FOR EACH ROW EXECUTE FUNCTION public.cascade_profile_fts_update();

-- =====================================
-- DELETION LOG TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER log_giveaways_deletions 
    AFTER DELETE ON public.giveaways 
    FOR EACH ROW EXECUTE FUNCTION public.log_deletion();

CREATE OR REPLACE TRIGGER log_lists_deletions 
    AFTER DELETE ON public.lists 
    FOR EACH ROW EXECUTE FUNCTION public.log_deletion();

CREATE OR REPLACE TRIGGER log_posts_deletions 
    AFTER DELETE ON public.posts 
    FOR EACH ROW EXECUTE FUNCTION public.log_deletion();

CREATE OR REPLACE TRIGGER log_products_deletions 
    AFTER DELETE ON public.products 
    FOR EACH ROW EXECUTE FUNCTION public.log_deletion();

CREATE OR REPLACE TRIGGER log_profile_deletions 
    AFTER DELETE ON public.profiles 
    FOR EACH ROW EXECUTE FUNCTION public.log_deletion();

-- =====================================
-- EMPLOYEE NOTIFICATION TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER on_employee_approval 
    AFTER UPDATE ON public.location_employees 
    FOR EACH ROW EXECUTE FUNCTION public.notify_employee_of_approval();

CREATE OR REPLACE TRIGGER on_employee_request 
    AFTER INSERT ON public.location_employees 
    FOR EACH ROW EXECUTE FUNCTION public.notify_brand_of_employee_request();

-- =====================================
-- PRODUCT BRANDS CACHE TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER product_brands_cache_update 
    AFTER INSERT OR DELETE OR UPDATE ON public.product_brands 
    FOR EACH ROW EXECUTE FUNCTION public.cascade_product_brands_update();

-- =====================================
-- FEATURED ITEMS SORT ORDER TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER set_featured_item_sort_order_before_insert 
    BEFORE INSERT ON public.featured_items 
    FOR EACH ROW EXECUTE FUNCTION public.set_initial_featured_item_sort_order();

-- =====================================
-- NOTIFICATION IMAGE URL TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER set_notification_image_url 
    AFTER INSERT ON public.notifications 
    FOR EACH ROW EXECUTE FUNCTION public.update_notification_image_url();

-- =====================================
-- SUBSCRIPTION COUNT TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER subscription_count_trigger 
    AFTER INSERT OR DELETE ON public.subscriptions_lists 
    FOR EACH ROW EXECUTE FUNCTION public.update_subscription_count();

-- =====================================
-- PROFILE SET CLAIMED TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER trg_profile_set_claimed 
    AFTER INSERT ON public.profile_admins 
    FOR EACH ROW EXECUTE FUNCTION public._fn_profile_set_claimed();

-- =====================================
-- RELATIONSHIP ROLE ID TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER trg_add_role_id_to_relationship 
    BEFORE INSERT ON public.relationships 
    FOR EACH ROW EXECUTE FUNCTION public.fn_add_role_id_to_relationship();

-- =====================================
-- ANALYTICS POST TRIGGER
-- =====================================

CREATE OR REPLACE TRIGGER trg_analytics_post 
    AFTER INSERT ON public.analytics_posts 
    FOR EACH ROW EXECUTE FUNCTION public.fn_analytics_post();

-- =====================================
-- COUNT UPDATE TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER trg_brand_count_on_products 
    AFTER INSERT OR DELETE ON public.product_brands 
    FOR EACH ROW EXECUTE FUNCTION public.fn_brand_count_on_products();

CREATE OR REPLACE TRIGGER trg_change_category_product_count_on_product 
    AFTER INSERT OR DELETE ON public.products 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_category_product_count_on_product();

CREATE OR REPLACE TRIGGER trg_change_claimed_deals_count_on_deals 
    AFTER INSERT OR DELETE ON public.deal_claims 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_deal_count_on_deals();

CREATE OR REPLACE TRIGGER trg_change_post_count_on_profiles 
    AFTER INSERT OR DELETE ON public.posts 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_post_count_on_profiles();

CREATE OR REPLACE TRIGGER trg_change_post_product_count_on_product 
    AFTER INSERT OR DELETE ON public.posts_products 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_post_product_count_on_product();

CREATE OR REPLACE TRIGGER trg_change_product_count_on_profiles 
    AFTER INSERT OR DELETE ON public.product_brands 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_product_count_on_profiles();

CREATE OR REPLACE TRIGGER trg_location_count_on_profile 
    AFTER INSERT OR DELETE ON public.locations 
    FOR EACH ROW EXECUTE FUNCTION public.fn_location_count_on_profile();

CREATE OR REPLACE TRIGGER trg_flag_count_on_posts 
    AFTER INSERT OR DELETE ON public.post_flags 
    FOR EACH ROW EXECUTE FUNCTION public.fn_flag_count_on_posts();

CREATE OR REPLACE TRIGGER trg_giveaway_entry_count_on_giveaway 
    AFTER INSERT OR DELETE ON public.giveaway_entries 
    FOR EACH ROW EXECUTE FUNCTION public.fn_giveaway_entry_count_on_giveaway();

CREATE OR REPLACE TRIGGER update_follower_count_on_profiles 
    AFTER INSERT OR DELETE ON public.relationships 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_follower_count();

CREATE OR REPLACE TRIGGER update_like_count_on_posts 
    AFTER INSERT OR DELETE ON public.likes 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_posts_like_count();

CREATE OR REPLACE TRIGGER update_like_count_on_profiles 
    AFTER INSERT OR DELETE ON public.likes 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_profiles_like_count();

CREATE OR REPLACE TRIGGER update_list_count_on_products 
    AFTER INSERT OR DELETE ON public.lists_products 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_product_list_count();

CREATE OR REPLACE TRIGGER update_product_count_on_list 
    AFTER INSERT OR DELETE ON public.lists_products 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_lists_product_count();

CREATE OR REPLACE TRIGGER update_stash_count_on_products 
    AFTER INSERT OR DELETE ON public.stash 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_product_stash_count();

CREATE OR REPLACE TRIGGER update_stash_count_on_profiles 
    AFTER INSERT OR DELETE ON public.stash 
    FOR EACH ROW EXECUTE FUNCTION public.fn_change_profiles_stash_count();

-- =====================================
-- ENTITY LIFECYCLE TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER trg_delete_product 
    BEFORE DELETE ON public.products 
    FOR EACH ROW EXECUTE FUNCTION public._fn_delete_product_trigger();

CREATE OR REPLACE TRIGGER trg_delete_remote_file_on_delete_from_cloud_files 
    AFTER DELETE ON public.cloud_files 
    FOR EACH ROW EXECUTE FUNCTION public.fn_delete_remote_file_on_delete();

CREATE OR REPLACE TRIGGER trg_location_on_update 
    AFTER INSERT OR UPDATE ON public.locations 
    FOR EACH ROW EXECUTE FUNCTION public._fn_location_on_update();

CREATE OR REPLACE TRIGGER trg_giveaway_entry_triggers 
    AFTER INSERT OR UPDATE ON public.giveaway_entries 
    FOR EACH ROW EXECUTE FUNCTION public.fn_giveaway_entry_triggers();

CREATE OR REPLACE TRIGGER trg_giveaway_triggers 
    AFTER INSERT ON public.giveaways 
    FOR EACH ROW EXECUTE FUNCTION public.fn_giveaway_triggers();

CREATE OR REPLACE TRIGGER trg_likes_insert_tasks 
    AFTER INSERT ON public.likes 
    FOR EACH ROW EXECUTE FUNCTION public._fn_likes_insert_tasks();

CREATE OR REPLACE TRIGGER trg_lists_products_sort 
    AFTER INSERT OR DELETE ON public.lists_products 
    FOR EACH ROW EXECUTE FUNCTION public.fn_lists_products_sort();

CREATE OR REPLACE TRIGGER trg_post_tasks 
    AFTER INSERT OR UPDATE ON public.posts 
    FOR EACH ROW EXECUTE FUNCTION public.fn_post_tasks();

CREATE OR REPLACE TRIGGER trg_product_post_insert_tasks 
    AFTER INSERT OR DELETE ON public.products 
    FOR EACH ROW EXECUTE FUNCTION public.fn_product_post_insert_tasks();

CREATE OR REPLACE TRIGGER trg_update_location_date_on_employee_add 
    AFTER INSERT OR DELETE ON public.location_employees 
    FOR EACH ROW EXECUTE FUNCTION public.fn_update_location_date_on_employee_add();

CREATE OR REPLACE TRIGGER trg_profile_admins_triggers 
    AFTER INSERT ON public.profile_admins 
    FOR EACH ROW EXECUTE FUNCTION public.fn_profile_admins_triggers();

CREATE OR REPLACE TRIGGER update_associated_data_trigger 
    AFTER UPDATE ON public.profiles 
    FOR EACH ROW WHEN ((pg_trigger_depth() = 0)) 
    EXECUTE FUNCTION public.update_associated_data();

-- =====================================
-- SLUG GENERATION TRIGGERS
-- =====================================

CREATE OR REPLACE TRIGGER trg_slug_on_name_on_locations 
    AFTER INSERT OR UPDATE ON public.locations 
    FOR EACH ROW EXECUTE FUNCTION public.set_slug_from_name();

CREATE OR REPLACE TRIGGER trg_slug_on_name_on_explore 
    AFTER INSERT ON public.explore 
    FOR EACH ROW EXECUTE FUNCTION public.set_slug_from_name();

CREATE OR REPLACE TRIGGER trg_slug_on_name_on_product_category 
    AFTER INSERT ON public.product_categories 
    FOR EACH ROW EXECUTE FUNCTION public.set_slug_from_name();

CREATE OR REPLACE TRIGGER trg_slug_product_insert 
    BEFORE INSERT ON public.products 
    FOR EACH ROW WHEN ((NEW.name IS NOT NULL AND NEW.slug IS NULL)) 
    EXECUTE FUNCTION public.set_slug_from_name();

CREATE OR REPLACE TRIGGER profile_slug_on_name_insert_update 
    BEFORE INSERT OR UPDATE ON public.profiles 
    FOR EACH ROW EXECUTE FUNCTION public.set_slug_from_name();
