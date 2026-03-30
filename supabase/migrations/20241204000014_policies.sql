-- Row Level Security Policies
-- RLS policies to control access to data
-- Updated: Uses profiles, locations, and new table/column names

-- =====================================
-- ENABLE ROW LEVEL SECURITY ON ALL TABLES
-- =====================================

-- Core tables
ALTER TABLE public.addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cloud_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deal_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deals_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations_cloud_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_stashlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_page ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_page_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explore_trending ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorite_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.featured_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.giveaway_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.giveaway_entries_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.giveaways ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.giveaways_regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lists_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.postal_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts_hashtags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.posts_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_feature_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products_cloud_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products_product_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.related_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_now ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stash ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.states ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deletion_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.region_postal_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.us_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_delete_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Directus tables
ALTER TABLE public.directus_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_dashboards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_fields ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_flows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_migrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_panels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.directus_webhooks ENABLE ROW LEVEL SECURITY;

-- =====================================
-- PUBLIC READ ACCESS POLICIES
-- (viewable by everyone)
-- =====================================

CREATE POLICY "cloud_files are viewable by everyone." ON public.cloud_files 
    FOR SELECT USING (true);

CREATE POLICY "deals are viewable by everyone." ON public.deals 
    FOR SELECT USING (true);

CREATE POLICY "deals_locations are viewable by everyone." ON public.deals_locations 
    FOR SELECT USING (true);

CREATE POLICY "locations are viewable by everyone." ON public.locations 
    FOR SELECT USING (true);

CREATE POLICY "locations_cloud_files are viewable by everyone." ON public.locations_cloud_files 
    FOR SELECT USING (true);

CREATE POLICY "likes are viewable by everyone." ON public.deal_claims 
    FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "likes are viewable by everyone." ON public.likes 
    FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "lists_products are viewable by everyone." ON public.lists_products 
    FOR SELECT USING (true);

CREATE POLICY "post_tags are viewable by everyone." ON public.post_tags 
    FOR SELECT USING (true);

CREATE POLICY "postal_codes are viewable by everyone." ON public.postal_codes 
    FOR SELECT USING (true);

CREATE POLICY "posts are viewable by everyone." ON public.posts 
    FOR SELECT USING (true);

CREATE POLICY "posts_hashtags are viewable by everyone." ON public.posts_hashtags 
    FOR SELECT USING (true);

CREATE POLICY "posts_products are viewable by everyone." ON public.posts_products 
    FOR SELECT USING (true);

CREATE POLICY "product_feature_types are viewable by everyone." ON public.product_feature_types 
    FOR SELECT USING (true);

CREATE POLICY "product_features are viewable by everyone." ON public.product_features 
    FOR SELECT USING (true);

CREATE POLICY "products are viewable by everyone." ON public.products 
    FOR SELECT USING (true);

CREATE POLICY "product_brands are viewable by everyone." ON public.product_brands 
    FOR SELECT USING (true);

CREATE POLICY "product_variants are viewable by everyone." ON public.product_variants 
    FOR SELECT USING (true);

CREATE POLICY "products_cloud_files are viewable by everyone." ON public.products_cloud_files 
    FOR SELECT USING (true);

CREATE POLICY "products_product_features are viewable by everyone." ON public.products_product_features 
    FOR SELECT USING (true);

CREATE POLICY "related_products are viewable by everyone." ON public.related_products 
    FOR SELECT USING (true);

CREATE POLICY "products_states are viewable by everyone." ON public.products_states 
    FOR SELECT USING (true);

CREATE POLICY "relationships are viewable by everyone." ON public.relationships 
    FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "roles are viewable by everyone." ON public.roles 
    FOR SELECT USING (true);

CREATE POLICY "stash are viewable by everyone." ON public.stash 
    FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "states are viewable by everyone." ON public.states 
    FOR SELECT USING (true);

CREATE POLICY "subscriptions_lists are viewable by everyone." ON public.subscriptions_lists 
    FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "us_locations are viewable by everyone." ON public.us_locations 
    FOR SELECT USING (true);

-- =====================================
-- GENERAL READ ACCESS POLICIES
-- =====================================

CREATE POLICY "All profiles can select" ON public.favorite_locations 
    FOR SELECT USING (true);

CREATE POLICY "Allow authenticated read access" ON public.featured_items 
    FOR SELECT USING ((auth.role() = 'authenticated'::text));

CREATE POLICY "Enable read access for owner" ON public.analytics_posts 
    FOR SELECT USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable read access for all users" ON public.location_employees 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.location_stashlists 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_locations 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_lists 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_posts 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_products 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_profiles 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.giveaways 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.giveaways_regions 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.notification_types 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.notifications 
    FOR SELECT USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = notifications.profile_id)
        ))
    ));

CREATE POLICY "Enable read access for all users" ON public.posts 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.posts_lists 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.posts_profiles 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.product_categories 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.push_queue 
    FOR SELECT USING ((
        SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable read access for all users" ON public.region_postal_codes 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.regions 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.shop_now 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.profile_admins 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.profiles 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users on lists" ON public.lists 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for authenticated users" ON public.notification_preferences 
    FOR SELECT USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable read access for authenticated users" ON public.push_tokens 
    FOR SELECT USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable read access to a profiles entries" ON public.giveaway_entries 
    FOR SELECT USING (true);

CREATE POLICY "Enable select for profiles based on profile_id on addresses" ON public.addresses 
    FOR SELECT USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

-- =====================================
-- SUPER ADMIN POLICIES
-- =====================================

CREATE POLICY "Allow super admins full access" ON public.featured_items 
    USING ((
        (SELECT p.role_id FROM public.profiles p WHERE (p.auth_id = auth.uid())) = 9
    ));

-- =====================================
-- INSERT POLICIES
-- =====================================

CREATE POLICY "Enable addresses insert for authenticated users only" ON public.addresses 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for admin users only" ON public.giveaways 
    FOR INSERT TO authenticated 
    WITH CHECK ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable insert for authenticated users only" ON public.location_employees 
    FOR INSERT TO authenticated 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = (
                SELECT locations.brand_id
                FROM public.locations
                WHERE (locations.id = location_employees.location_id)
            ))
        )) OR 
        (SELECT (le1.role = 'manager')
            FROM public.location_employees le1
            JOIN public.profiles p ON p.id = le1.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable insert for authenticated users only" ON public.locations 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.locations_cloud_files 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.location_stashlists 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.giveaway_entries 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.giveaways_regions 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.lists_products 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.post_flags 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.post_tags 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.posts_lists 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.posts_profiles 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.product_categories 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.product_feature_types 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.product_features 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.products 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.product_brands 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.product_variants 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.products_cloud_files 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.products_product_features 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.related_products 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.push_queue 
    FOR INSERT TO authenticated 
    WITH CHECK ((
        SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable insert for authenticated users only" ON public.profile_blocks 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.profile_admins 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.profile_delete_requests 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.notification_preferences 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.push_tokens 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON public.profiles 
    FOR INSERT TO anon, authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only analytics" ON public.analytics_posts 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only cloud_files" ON public.cloud_files 
    FOR INSERT TO anon, authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only deal_claims" ON public.deal_claims 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only likes" ON public.likes 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only lists" ON public.lists 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only post_logs" ON public.post_log 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only posts" ON public.posts 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only posts_hashtags" ON public.posts_hashtags 
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only posts_products" ON public.posts_products 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only relationships" ON public.relationships 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only subscriptions_lists" ON public.subscriptions_lists 
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable insert for profiles based on profile_id" ON public.notifications 
    FOR INSERT WITH CHECK ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

-- =====================================
-- UPDATE POLICIES
-- =====================================

CREATE POLICY "Enable update for profiles based on brand admin" ON public.profiles 
    FOR UPDATE 
    USING ((
        (auth.uid() = auth_id) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = profiles.id)
        )) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    )) 
    WITH CHECK ((
        (auth.uid() = auth_id) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = profiles.id)
        )) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable update for profiles based on email" ON public.location_employees 
    FOR UPDATE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = (
                SELECT locations.brand_id
                FROM public.locations
                WHERE (locations.id = location_employees.location_id)
            ))
        )) OR 
        (SELECT (le1.role = 'manager')
            FROM public.location_employees le1
            JOIN public.profiles p ON p.id = le1.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    )) 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = (
                SELECT locations.brand_id
                FROM public.locations
                WHERE (locations.id = location_employees.location_id)
            ))
        )) OR 
        (SELECT (le1.role = 'manager')
            FROM public.location_employees le1
            JOIN public.profiles p ON p.id = le1.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable update for profiles based on email" ON public.locations 
    FOR UPDATE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = brand_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = locations.brand_id)
        )) OR 
        (SELECT (location_employees.role = 'manager')
            FROM public.location_employees
            JOIN public.profiles p ON p.id = location_employees.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations.id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = brand_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = locations.brand_id)
        )) OR 
        (SELECT (location_employees.role = 'manager')
            FROM public.location_employees
            JOIN public.profiles p ON p.id = location_employees.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations.id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable update for profiles based on email" ON public.lists 
    FOR UPDATE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = lists.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = lists.profile_id)
        ))
    ));

CREATE POLICY "Enable update for profiles based on email" ON public.post_tags 
    FOR UPDATE TO authenticated 
    USING (true) 
    WITH CHECK (true);

CREATE POLICY "Enable update for profiles based on email" ON public.products 
    FOR UPDATE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT product_brands.brand_id
                FROM public.product_brands
                WHERE (product_brands.product_id = products.id)
            ))
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    )) 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT product_brands.brand_id
                FROM public.product_brands
                WHERE (product_brands.product_id = products.id)
            ))
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable update for profiles based on email" ON public.push_queue 
    FOR UPDATE 
    USING ((
        SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    )) 
    WITH CHECK ((
        SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable update for profiles based on email" ON public.notification_preferences 
    FOR UPDATE 
    USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id))) 
    WITH CHECK ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable update for profiles based on email" ON public.push_tokens 
    FOR UPDATE 
    USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id))) 
    WITH CHECK ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable update for profiles based on role id" ON public.giveaway_entries 
    FOR UPDATE 
    USING ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    )) 
    WITH CHECK ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable update for profiles based on role id" ON public.giveaways 
    FOR UPDATE 
    USING ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    )) 
    WITH CHECK ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable update for profiles based on uid" ON public.addresses 
    FOR UPDATE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = addresses.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = addresses.profile_id)
        ))
    ));

CREATE POLICY "Enable update for profiles based on uid" ON public.notifications 
    FOR UPDATE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = notifications.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = notifications.profile_id)
        ))
    ));

CREATE POLICY "Enable update for profiles based on uid" ON public.posts 
    FOR UPDATE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = posts.profile_id)
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = posts.profile_id)
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable update for profiles based on profile_id" ON public.location_stashlists 
    FOR UPDATE USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

-- =====================================
-- DELETE POLICIES
-- =====================================

CREATE POLICY "Enable delete for profiles" ON public.post_tags 
    FOR DELETE TO authenticated USING (true);

CREATE POLICY "Enable delete for profiles based on role id" ON public.giveaways 
    FOR DELETE 
    USING ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.addresses 
    FOR DELETE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = addresses.profile_id)
        ))
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.location_employees 
    FOR DELETE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = (
                SELECT locations.brand_id
                FROM public.locations
                WHERE (locations.id = location_employees.location_id)
            ))
        )) OR 
        (SELECT (le1.role = 'manager')
            FROM public.location_employees le1
            JOIN public.profiles p ON p.id = le1.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (le1.location_id = location_employees.location_id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.locations 
    FOR DELETE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = brand_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = locations.brand_id)
        )) OR 
        (SELECT (location_employees.role = 'manager')
            FROM public.location_employees
            JOIN public.profiles p ON p.id = location_employees.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations.id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.locations_cloud_files 
    FOR DELETE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = (SELECT brand_id FROM locations WHERE id = locations_cloud_files.location_id))
        )) OR 
        (SELECT (location_employees.role = 'manager')
            FROM public.location_employees
            JOIN public.profiles p ON p.id = location_employees.profile_id
            WHERE ((p.auth_id = auth.uid()) AND (location_employees.location_id = locations_cloud_files.location_id))
        ) OR 
        (SELECT (p1.role_id <= 9 OR p1.role_id >= 3) AS bool
            FROM public.profiles p1
            WHERE (p1.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.location_stashlists 
    FOR DELETE USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.post_flags 
    FOR DELETE USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.posts_hashtags 
    FOR DELETE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_hashtags.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_hashtags.post_id)
            ))
        ))
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.products 
    FOR DELETE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT product_brands.brand_id
                FROM public.product_brands
                WHERE (product_brands.product_id = products.id)
            ))
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.product_brands 
    FOR DELETE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = brand_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = product_brands.brand_id)
        ))
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.products_cloud_files 
    FOR DELETE 
    USING ((
        auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT product_brands.brand_id
                FROM public.product_brands
                WHERE (product_brands.product_id = products_cloud_files.product_id)
            ))
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.products_product_features 
    FOR DELETE 
    USING ((
        auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT product_brands.brand_id
                FROM public.product_brands
                WHERE (product_brands.product_id = products_product_features.product_id)
            ))
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.related_products 
    FOR DELETE 
    USING ((
        auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT product_brands.brand_id
                FROM public.product_brands
                WHERE (product_brands.product_id = related_products.product_id)
            ))
        )
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.push_queue 
    FOR DELETE 
    USING ((
        SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.profile_blocks 
    FOR DELETE USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.profile_admins 
    FOR DELETE 
    USING ((
        SELECT (p.role_id <= 9 OR p.role_id >= 3) AS bool
        FROM public.profiles p
        WHERE (p.auth_id = auth.uid())
    ));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.notification_preferences 
    FOR DELETE USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable delete for profiles based on profile_id" ON public.push_tokens 
    FOR DELETE USING ((auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)));

CREATE POLICY "Enable delete for profiles based on profile_id from lists" ON public.lists_products 
    FOR DELETE 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.lists
            JOIN public.profiles p ON p.id = lists.profile_id
            WHERE (lists.id = lists_products.list_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT lists.profile_id
                FROM public.lists
                WHERE (lists.id = lists_products.list_id)
            ))
        ))
    ));

CREATE POLICY "Enable delete for profiles based on profile_id on lists" ON public.lists 
    FOR DELETE 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = lists.profile_id)
        ))
    ));

-- =====================================
-- COMBINED CRUD POLICIES
-- =====================================

CREATE POLICY "Enable all access for all owners" ON public.posts_lists 
    TO authenticated 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_lists.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_lists.post_id)
            ))
        ))
    )) 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_lists.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_lists.post_id)
            ))
        ))
    ));

CREATE POLICY "Enable all for profile" ON public.posts_profiles 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_profiles.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_profiles.post_id)
            ))
        ))
    )) 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_profiles.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_profiles.post_id)
            ))
        ))
    ));

CREATE POLICY "Profile has all rights" ON public.favorite_locations 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = favorite_locations.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = favorite_locations.profile_id)
        ))
    ));

CREATE POLICY "Profiles can add and remove lists_products." ON public.lists_products 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.lists
            JOIN public.profiles p ON p.id = lists.profile_id
            WHERE (lists.id = lists_products.list_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT lists.profile_id
                FROM public.lists
                WHERE (lists.id = lists_products.list_id)
            ))
        ))
    )) 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.lists
            JOIN public.profiles p ON p.id = lists.profile_id
            WHERE (lists.id = lists_products.list_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT lists.profile_id
                FROM public.lists
                WHERE (lists.id = lists_products.list_id)
            ))
        ))
    ));

CREATE POLICY "Profiles can add and remove posts_products." ON public.posts_products 
    USING ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_products.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_products.post_id)
            ))
        ))
    )) 
    WITH CHECK ((
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.posts
            JOIN public.profiles p ON p.id = posts.profile_id
            WHERE (posts.id = posts_products.post_id)
        )) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id IN (
                SELECT posts.profile_id
                FROM public.posts
                WHERE (posts.id = posts_products.post_id)
            ))
        ))
    ));

CREATE POLICY "Profiles can have all permissions for cloud files." ON public.cloud_files 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = cloud_files.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = cloud_files.profile_id)
        ))
    ));

CREATE POLICY "Profiles can have all permissions for deal_claims." ON public.deal_claims 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = deal_claims.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = deal_claims.profile_id)
        ))
    ));

CREATE POLICY "Profiles can have all permissions for likes." ON public.likes 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = likes.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = likes.profile_id)
        ))
    ));

CREATE POLICY "Profiles can have all permissions for posts." ON public.posts 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = posts.profile_id)
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = posts.profile_id)
        )) OR 
        (SELECT (p.role_id <= 9 OR p.role_id > 3) AS bool
            FROM public.profiles p
            WHERE (p.auth_id = auth.uid())
        )
    ));

CREATE POLICY "Profiles can have all permissions for relationships." ON public.relationships 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = follower_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = relationships.follower_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = follower_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = relationships.follower_id)
        ))
    ));

CREATE POLICY "Profiles can have all permissions for stash." ON public.stash 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = stash.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = stash.profile_id)
        ))
    ));

CREATE POLICY "Profiles can have all permissions for subscriptions_lists." ON public.subscriptions_lists 
    USING ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = subscriptions_lists.profile_id)
        ))
    )) 
    WITH CHECK ((
        (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id)) OR 
        (auth.uid() IN (
            SELECT p.auth_id
            FROM public.profile_admins pa
            JOIN public.profiles p ON p.id = pa.admin_profile_id
            WHERE (pa.managed_profile_id = subscriptions_lists.profile_id)
        ))
    ));

-- =====================================
-- ADDITIONAL TABLE POLICIES
-- =====================================

-- Deletion log - service role only (audit table)
CREATE POLICY "Service role only" ON public.deletion_log
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Explore page tables - public read access
CREATE POLICY "Enable read access for all users" ON public.explore_page 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_page_sections 
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON public.explore_trending 
    FOR SELECT USING (true);

-- Giveaway entries messages - users can see their own messages
CREATE POLICY "Users can view their own giveaway messages" ON public.giveaway_entries_messages 
    FOR SELECT USING ((
        auth.uid() = (
            SELECT p.auth_id 
            FROM profiles p 
            JOIN giveaway_entries ge ON ge.profile_id = p.id 
            WHERE ge.id = giveaway_entry_id
        )
    ));

CREATE POLICY "Users can insert their own giveaway messages" ON public.giveaway_entries_messages 
    FOR INSERT WITH CHECK ((
        auth.uid() = (
            SELECT p.auth_id 
            FROM profiles p 
            JOIN giveaway_entries ge ON ge.profile_id = p.id 
            WHERE ge.id = giveaway_entry_id
        )
    ));
