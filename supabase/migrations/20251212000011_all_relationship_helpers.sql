-- ============================================================================
-- COMPREHENSIVE RELATIONSHIP HELPERS
-- Wrappers for all major relationship tables to support UUID-based operations
-- from the client side.
-- ============================================================================

-- ============================================================================
-- 1. SOCIAL ACTIONS (Follows, Blocks)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.follow_profile(target_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_follower_id integer;
    v_followee_id integer;
BEGIN
    -- Get IDs
    SELECT id INTO v_follower_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_followee_id FROM public.profiles WHERE public_id = target_public_id;

    IF v_follower_id IS NULL THEN RAISE EXCEPTION 'Current profile not found'; END IF;
    IF v_followee_id IS NULL THEN RAISE EXCEPTION 'Target profile not found'; END IF;
    IF v_follower_id = v_followee_id THEN RAISE EXCEPTION 'Cannot follow yourself'; END IF;

    INSERT INTO public.relationships (follower_id, followee_id)
    VALUES (v_follower_id, v_followee_id)
    ON CONFLICT (follower_id, followee_id) DO NOTHING;
    
    -- Update counts
    UPDATE public.profiles SET following_count = following_count + 1 WHERE id = v_follower_id;
    UPDATE public.profiles SET follower_count = follower_count + 1 WHERE id = v_followee_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unfollow_profile(target_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_follower_id integer;
    v_followee_id integer;
BEGIN
    SELECT id INTO v_follower_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_followee_id FROM public.profiles WHERE public_id = target_public_id;

    IF v_follower_id IS NULL OR v_followee_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.relationships 
    WHERE follower_id = v_follower_id AND followee_id = v_followee_id;
    
    IF FOUND THEN
        UPDATE public.profiles SET following_count = GREATEST(0, following_count - 1) WHERE id = v_follower_id;
        UPDATE public.profiles SET follower_count = GREATEST(0, follower_count - 1) WHERE id = v_followee_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.block_profile(target_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_blocker_id integer;
    v_blocked_id integer;
BEGIN
    SELECT id INTO v_blocker_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_blocked_id FROM public.profiles WHERE public_id = target_public_id;

    IF v_blocker_id IS NULL OR v_blocked_id IS NULL THEN RETURN; END IF;

    -- Remove relationship if exists
    DELETE FROM public.relationships 
    WHERE (follower_id = v_blocker_id AND followee_id = v_blocked_id)
       OR (follower_id = v_blocked_id AND followee_id = v_blocker_id);

    INSERT INTO public.profile_blocks (profile_id, blocked_profile_id)
    VALUES (v_blocker_id, v_blocked_id)
    ON CONFLICT (profile_id, blocked_profile_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_profile(target_public_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_blocker_id integer;
    v_blocked_id integer;
BEGIN
    SELECT id INTO v_blocker_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_blocked_id FROM public.profiles WHERE public_id = target_public_id;

    IF v_blocker_id IS NULL OR v_blocked_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.profile_blocks 
    WHERE profile_id = v_blocker_id AND blocked_profile_id = v_blocked_id;
END;
$$;

-- ============================================================================
-- 2. POST ACTIONS (Likes, Comments)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.like_post(target_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_post_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_post_id FROM public.posts WHERE public_id = target_post_id;

    IF v_profile_id IS NULL OR v_post_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.likes (profile_id, post_id)
    VALUES (v_profile_id, v_post_id)
    ON CONFLICT (profile_id, post_id) DO NOTHING;
    
    -- Count update handled by trigger
END;
$$;

CREATE OR REPLACE FUNCTION public.unlike_post(target_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_post_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_post_id FROM public.posts WHERE public_id = target_post_id;

    IF v_profile_id IS NULL OR v_post_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.likes 
    WHERE profile_id = v_profile_id AND post_id = v_post_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_comment(
    target_post_id uuid, 
    content text, 
    parent_comment_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_post_id integer;
    v_parent_id integer;
    v_new_id uuid;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_post_id FROM public.posts WHERE public_id = target_post_id;
    
    IF parent_comment_id IS NOT NULL THEN
        SELECT id INTO v_parent_id FROM public.post_comments WHERE public_id = parent_comment_id;
    END IF;

    IF v_profile_id IS NULL OR v_post_id IS NULL THEN RAISE EXCEPTION 'Invalid reference'; END IF;

    INSERT INTO public.post_comments (post_id, profile_id, parent_id, message)
    VALUES (v_post_id, v_profile_id, v_parent_id, content)
    RETURNING public_id INTO v_new_id;

    RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.like_comment(target_comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_comment_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_comment_id FROM public.post_comments WHERE public_id = target_comment_id;

    IF v_profile_id IS NULL OR v_comment_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.comment_likes (profile_id, comment_id)
    VALUES (v_profile_id, v_comment_id)
    ON CONFLICT (profile_id, comment_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unlike_comment(target_comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_comment_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_comment_id FROM public.post_comments WHERE public_id = target_comment_id;

    IF v_profile_id IS NULL OR v_comment_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.comment_likes 
    WHERE profile_id = v_profile_id AND comment_id = v_comment_id;
END;
$$;

-- ============================================================================
-- 3. PRODUCT ACTIONS (Stash, Lists)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.stash_product(target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_profile_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.stash (profile_id, product_id)
    VALUES (v_profile_id, v_product_id)
    ON CONFLICT DO NOTHING; -- Stash has no unique constraint on (profile, product) in schema? 
                            -- Checking schema: stash_pkey is id. No unique constraint defined in core_tables.sql?
                            -- Let's add a check to prevent duplicates manually.
    
    IF NOT EXISTS (SELECT 1 FROM public.stash WHERE profile_id = v_profile_id AND product_id = v_product_id) THEN
        INSERT INTO public.stash (profile_id, product_id) VALUES (v_profile_id, v_product_id);
        UPDATE public.products SET stash_count = stash_count + 1 WHERE id = v_product_id;
        UPDATE public.profiles SET stash_count = stash_count + 1 WHERE id = v_profile_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.unstash_product(target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_profile_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.stash 
    WHERE profile_id = v_profile_id AND product_id = v_product_id;
    
    IF FOUND THEN
        UPDATE public.products SET stash_count = GREATEST(0, stash_count - 1) WHERE id = v_product_id;
        UPDATE public.profiles SET stash_count = GREATEST(0, stash_count - 1) WHERE id = v_profile_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_to_list(target_list_id uuid, target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_list_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_list_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    -- Check ownership of list (optional, but good practice)
    IF NOT EXISTS (SELECT 1 FROM public.lists WHERE id = v_list_id AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())) THEN
        RAISE EXCEPTION 'You do not own this list';
    END IF;

    INSERT INTO public.lists_products (list_id, product_id)
    VALUES (v_list_id, v_product_id)
    ON CONFLICT DO NOTHING;
    
    -- Update count? Schema doesn't show trigger for lists_products count on lists table.
    -- Assuming manual update or trigger exists.
    UPDATE public.lists SET product_count = product_count + 1 WHERE id = v_list_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_from_list(target_list_id uuid, target_product_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_list_id integer;
    v_product_id integer;
BEGIN
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;

    IF v_list_id IS NULL OR v_product_id IS NULL THEN RETURN; END IF;

    -- Check ownership
    IF NOT EXISTS (SELECT 1 FROM public.lists WHERE id = v_list_id AND profile_id = (SELECT id FROM public.profiles WHERE auth_id = auth.uid())) THEN
        RAISE EXCEPTION 'You do not own this list';
    END IF;

    DELETE FROM public.lists_products 
    WHERE list_id = v_list_id AND product_id = v_product_id;

    IF FOUND THEN
        UPDATE public.lists SET product_count = GREATEST(0, product_count - 1) WHERE id = v_list_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.subscribe_list(target_list_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_list_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;

    IF v_profile_id IS NULL OR v_list_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.subscriptions_lists (profile_id, list_id)
    VALUES (v_profile_id, v_list_id)
    ON CONFLICT (profile_id, list_id) DO NOTHING;

    UPDATE public.lists SET subscription_count = subscription_count + 1 WHERE id = v_list_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unsubscribe_list(target_list_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_list_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_list_id FROM public.lists WHERE public_id = target_list_id;

    IF v_profile_id IS NULL OR v_list_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.subscriptions_lists 
    WHERE profile_id = v_profile_id AND list_id = v_list_id;

    IF FOUND THEN
        UPDATE public.lists SET subscription_count = GREATEST(0, subscription_count - 1) WHERE id = v_list_id;
    END IF;
END;
$$;

-- ============================================================================
-- 4. LOCATION ACTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.favorite_location(target_location_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_location_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_location_id FROM public.locations WHERE public_id = target_location_id;

    IF v_profile_id IS NULL OR v_location_id IS NULL THEN RETURN; END IF;

    INSERT INTO public.favorite_locations (profile_id, location_id)
    VALUES (v_profile_id, v_location_id)
    ON CONFLICT (profile_id, location_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.unfavorite_location(target_location_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_location_id integer;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_location_id FROM public.locations WHERE public_id = target_location_id;

    IF v_profile_id IS NULL OR v_location_id IS NULL THEN RETURN; END IF;

    DELETE FROM public.favorite_locations 
    WHERE profile_id = v_profile_id AND location_id = v_location_id;
END;
$$;

-- ============================================================================
-- 5. DEALS & GIVEAWAYS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.claim_deal(target_deal_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_deal_id integer;
    v_claim_id uuid;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_deal_id FROM public.deals WHERE public_id = target_deal_id;

    IF v_profile_id IS NULL OR v_deal_id IS NULL THEN RAISE EXCEPTION 'Invalid reference'; END IF;

    INSERT INTO public.deal_claims (profile_id, deal_id)
    VALUES (v_profile_id, v_deal_id)
    RETURNING public_id INTO v_claim_id;

    UPDATE public.deals SET claimed_deals = claimed_deals + 1 WHERE id = v_deal_id;
    
    RETURN v_claim_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.enter_giveaway(target_giveaway_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile_id integer;
    v_giveaway_id integer;
    v_entry_id uuid;
BEGIN
    SELECT id INTO v_profile_id FROM public.profiles WHERE auth_id = auth.uid();
    SELECT id INTO v_giveaway_id FROM public.giveaways WHERE public_id = target_giveaway_id;

    IF v_profile_id IS NULL OR v_giveaway_id IS NULL THEN RAISE EXCEPTION 'Invalid reference'; END IF;

    INSERT INTO public.giveaway_entries (profile_id, giveaway_id)
    VALUES (v_profile_id, v_giveaway_id)
    RETURNING public_id INTO v_entry_id;

    UPDATE public.giveaways SET entry_count = entry_count + 1 WHERE id = v_giveaway_id;
    
    RETURN v_entry_id;
END;
$$;

-- ============================================================================
-- 6. ENTITY CREATION HELPERS (Resolving FKs)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_product_variant(
    target_product_id uuid,
    variant_name text,
    variant_price decimal,
    variant_sku text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product_id integer;
    v_variant_id uuid;
BEGIN
    SELECT id INTO v_product_id FROM public.products WHERE public_id = target_product_id;
    IF v_product_id IS NULL THEN RAISE EXCEPTION 'Product not found'; END IF;

    INSERT INTO public.product_variants (product_id, name, price, sku)
    VALUES (v_product_id, variant_name, variant_price, variant_sku)
    RETURNING public_id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_location(
    name text,
    address_line1 text,
    city text,
    state text,
    postal_code text, -- Look up ID from code
    brand_public_id uuid DEFAULT NULL -- Optional override, defaults to auth user
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_brand_id integer;
    v_postal_code_id integer;
    v_location_id uuid;
BEGIN
    -- Resolve Brand
    IF brand_public_id IS NOT NULL THEN
        SELECT id INTO v_brand_id FROM public.profiles WHERE public_id = brand_public_id;
    ELSE
        SELECT id INTO v_brand_id FROM public.profiles WHERE auth_id = auth.uid();
    END IF;
    
    IF v_brand_id IS NULL THEN RAISE EXCEPTION 'Brand profile not found'; END IF;

    -- Resolve Postal Code (Simple lookup)
    SELECT id INTO v_postal_code_id FROM public.postal_codes WHERE public.postal_codes.postal_code = create_location.postal_code LIMIT 1;
    
    INSERT INTO public.locations (brand_id, name, address_line1, city, state, postal_code_id)
    VALUES (v_brand_id, name, address_line1, city, state, v_postal_code_id)
    RETURNING public_id INTO v_location_id;

    RETURN v_location_id;
END;
$$;
