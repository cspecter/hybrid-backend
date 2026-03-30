-- ============================================================================
-- FIX RELATIONSHIPS MIGRATION
-- Run this to update existing records with correct foreign keys
-- based on public_id (UUID) matching
-- ============================================================================

-- Disable triggers to avoid FTS updates and other side effects during bulk update
SET session_replication_role = replica;

-- ============================================================================
-- PART 0: REPAIR CLOUD FILES (Ensure public_id matches old UUID)
-- ============================================================================
UPDATE public.cloud_files pcf
SET public_id = mcf.old_uuid
FROM migration_export.cloud_files mcf
WHERE pcf.id = mcf.new_id
  AND pcf.public_id != mcf.old_uuid;

-- ============================================================================
-- PART 1: UPDATE BASE TABLES (Foreign Keys)
-- ============================================================================

-- 1.1 PROFILES (Avatar, Banner)
UPDATE public.profiles p
SET 
    avatar_id = cf_avatar.id,
    banner_id = cf_banner.id
FROM migration_export.profiles mp
LEFT JOIN public.cloud_files cf_avatar ON mp.original_avatar_uuid = cf_avatar.public_id
LEFT JOIN public.cloud_files cf_banner ON mp.original_banner_uuid = cf_banner.public_id
WHERE p.public_id = mp.public_id;

-- 1.2 LOCATIONS (Brand, Banner, Logo)
UPDATE public.locations l
SET 
    brand_id = brand.id,
    banner_id = cf_banner.id,
    logo_id = cf_logo.id
FROM migration_export.locations ml
LEFT JOIN public.profiles brand ON ml.original_brand_uuid = brand.public_id
LEFT JOIN public.cloud_files cf_banner ON ml.original_banner_uuid = cf_banner.public_id
LEFT JOIN public.cloud_files cf_logo ON ml.original_logo_uuid = cf_logo.public_id
WHERE l.public_id = ml.public_id;

-- 1.3 PRODUCTS (Category, Thumbnail, Cover)
UPDATE public.products p
SET 
    category_id = cat.id,
    thumbnail_id = cf_thumb.id,
    cover_id = cf_cover.id
FROM migration_export.products mp
LEFT JOIN public.product_categories cat ON mp.original_category_uuid = cat.public_id
LEFT JOIN public.cloud_files cf_thumb ON mp.original_thumbnail_uuid = cf_thumb.public_id
LEFT JOIN public.cloud_files cf_cover ON mp.original_cover_uuid = cf_cover.public_id
WHERE p.public_id = mp.public_id;

-- 1.4 POSTS (Profile, File)
UPDATE public.posts p
SET 
    profile_id = prof.id,
    file_id = cf_file.id
FROM migration_export.posts mp
LEFT JOIN public.profiles prof ON mp.original_profile_uuid = prof.public_id
LEFT JOIN public.cloud_files cf_file ON mp.original_file_uuid = cf_file.public_id
WHERE p.public_id = mp.public_id;

-- 1.5 LISTS (Profile, Thumbnail, Background)
UPDATE public.lists l
SET 
    profile_id = prof.id,
    thumbnail_id = cf_thumb.id,
    background_id = cf_bg.id
FROM migration_export.lists ml
LEFT JOIN public.profiles prof ON ml.original_profile_uuid = prof.public_id
LEFT JOIN public.cloud_files cf_thumb ON ml.original_thumbnail_uuid = cf_thumb.public_id
LEFT JOIN public.cloud_files cf_bg ON ml.original_background_uuid = cf_bg.public_id
WHERE l.public_id = ml.public_id;

-- 1.6 DEALS (Product)
UPDATE public.deals d
SET 
    product_id = prod.id
FROM migration_export.deals md
LEFT JOIN public.products prod ON md.original_product_uuid = prod.public_id
WHERE d.public_id = md.public_id;

-- 1.7 GIVEAWAYS (Product, Cover)
UPDATE public.giveaways g
SET 
    product_id = prod.id,
    cover_id = cf_cover.id
FROM migration_export.giveaways mg
LEFT JOIN public.products prod ON mg.original_product_uuid = prod.public_id
LEFT JOIN public.cloud_files cf_cover ON mg.original_cover_uuid = cf_cover.public_id
WHERE g.public_id = mg.public_id;

-- 1.8 NOTIFICATIONS (Profile, Actor)
UPDATE public.notifications n
SET 
    profile_id = prof.id,
    actor_id = actor.id
FROM migration_export.notifications mn
LEFT JOIN public.profiles prof ON mn.original_profile_uuid = prof.public_id
LEFT JOIN public.profiles actor ON mn.original_actor_uuid = actor.public_id
WHERE n.public_id = mn.public_id;

-- 1.9 PRODUCT CATEGORIES (Parent, Image)
UPDATE public.product_categories pc
SET 
    parent_id = parent.id,
    image_id = cf_image.id
FROM migration_export.product_categories mpc
LEFT JOIN public.product_categories parent ON mpc.original_parent_uuid = parent.public_id
LEFT JOIN public.cloud_files cf_image ON mpc.original_image_uuid = cf_image.public_id
WHERE pc.public_id = mpc.public_id;

-- 1.10 EXPLORE (Thumbnail)
UPDATE public.explore e
SET 
    thumbnail_id = cf_thumb.id
FROM migration_export.explore me
LEFT JOIN public.cloud_files cf_thumb ON me.original_thumbnail_uuid = cf_thumb.public_id
WHERE e.id = me.id;

-- ============================================================================
-- PART 2: INSERT JUNCTION TABLES
-- ============================================================================

-- 2.1 LOCATION EMPLOYEES
INSERT INTO public.location_employees (id, location_id, profile_id, role, is_approved, has_been_reviewed, created_at, updated_at)
SELECT 
    mle.new_id,
    l.id,
    p.id,
    mle.role,
    mle.is_approved,
    mle.has_been_reviewed,
    mle.created_at,
    mle.updated_at
FROM migration_export.location_employees mle
JOIN public.locations l ON mle.original_location_uuid = l.public_id
JOIN public.profiles p ON mle.original_profile_uuid = p.public_id
ON CONFLICT DO NOTHING;

-- 2.2 PRODUCT BRANDS
INSERT INTO public.product_brands (id, product_id, brand_id, created_at)
SELECT 
    mpb.new_id,
    prod.id,
    brand.id,
    mpb.created_at
FROM migration_export.product_brands mpb
JOIN public.products prod ON mpb.original_product_uuid = prod.public_id
JOIN public.profiles brand ON mpb.original_brand_uuid = brand.public_id
ON CONFLICT DO NOTHING;

-- 2.3 RELATED PRODUCTS
INSERT INTO public.related_products (id, product_id, related_product_id, created_at)
SELECT 
    mrp.new_id,
    p1.id,
    p2.id,
    mrp.created_at
FROM migration_export.related_products mrp
JOIN public.products p1 ON mrp.original_product_uuid = p1.public_id
JOIN public.products p2 ON mrp.original_related_product_uuid = p2.public_id
ON CONFLICT DO NOTHING;

-- 2.4 DEALS LOCATIONS
INSERT INTO public.deals_locations (id, deal_id, location_id)
SELECT 
    mdl.new_id,
    d.id,
    l.id
FROM migration_export.deals_locations mdl
JOIN public.deals d ON mdl.original_deal_uuid = d.public_id
JOIN public.locations l ON mdl.original_location_uuid = l.public_id
ON CONFLICT DO NOTHING;

-- 2.5 PROFILE ADMINS
INSERT INTO public.profile_admins (id, admin_profile_id, managed_profile_id, created_at)
SELECT 
    mpa.new_id,
    admin.id,
    managed.id,
    mpa.created_at
FROM migration_export.profile_admins mpa
JOIN public.profiles admin ON mpa.original_admin_uuid = admin.public_id
JOIN public.profiles managed ON mpa.original_managed_uuid = managed.public_id
ON CONFLICT DO NOTHING;

-- 2.6 PROFILE BLOCKS
INSERT INTO public.profile_blocks (id, profile_id, blocked_profile_id, created_at)
SELECT 
    mpb.new_id,
    blocker.id,
    blocked.id,
    mpb.created_at
FROM migration_export.profile_blocks mpb
JOIN public.profiles blocker ON mpb.original_blocker_uuid = blocker.public_id
JOIN public.profiles blocked ON mpb.original_blocked_uuid = blocked.public_id
ON CONFLICT DO NOTHING;

-- 2.7 RELATIONSHIPS
INSERT INTO public.relationships (id, follower_id, followee_id, role_id, created_at, updated_at)
SELECT 
    mr.new_id,
    follower.id,
    followee.id,
    mr.role_id,
    mr.created_at,
    mr.updated_at
FROM migration_export.relationships mr
JOIN public.profiles follower ON mr.original_follower_uuid = follower.public_id
JOIN public.profiles followee ON mr.original_followee_uuid = followee.public_id
ON CONFLICT DO NOTHING;

-- 2.8 POSTS PROFILES
INSERT INTO public.posts_profiles (id, post_id, profile_id, created_at)
SELECT 
    mpp.new_id,
    post.id,
    prof.id,
    mpp.created_at
FROM migration_export.posts_profiles mpp
JOIN public.posts post ON mpp.original_post_uuid = post.public_id
JOIN public.profiles prof ON mpp.original_profile_uuid = prof.public_id
ON CONFLICT DO NOTHING;

-- 2.9 POSTS PRODUCTS
INSERT INTO public.posts_products (id, post_id, product_id, created_at)
SELECT 
    mpp.new_id,
    post.id,
    prod.id,
    mpp.created_at
FROM migration_export.posts_products mpp
JOIN public.posts post ON mpp.original_post_uuid = post.public_id
JOIN public.products prod ON mpp.original_product_uuid = prod.public_id
ON CONFLICT DO NOTHING;

-- 2.10 POSTS HASHTAGS
INSERT INTO public.posts_hashtags (id, post_id, post_tag_id, created_at, updated_at)
SELECT 
    mph.new_id,
    post.id,
    mph.post_tag_id,
    mph.created_at,
    mph.updated_at
FROM migration_export.posts_hashtags mph
JOIN public.posts post ON mph.original_post_uuid = post.public_id
ON CONFLICT DO NOTHING;

-- 2.11 POSTS LISTS
INSERT INTO public.posts_lists (id, post_id, list_id, created_at, updated_at)
SELECT 
    mpl.new_id,
    post.id,
    list.id,
    mpl.created_at,
    mpl.updated_at
FROM migration_export.posts_lists mpl
JOIN public.posts post ON mpl.original_post_uuid = post.public_id
JOIN public.lists list ON mpl.original_list_uuid = list.public_id
ON CONFLICT DO NOTHING;

-- 2.12 LISTS PRODUCTS
INSERT INTO public.lists_products (id, list_id, product_id, created_at)
SELECT 
    mlp.new_id,
    list.id,
    prod.id,
    mlp.created_at
FROM migration_export.lists_products mlp
JOIN public.lists list ON mlp.original_list_uuid = list.public_id
JOIN public.products prod ON mlp.original_product_uuid = prod.public_id
ON CONFLICT DO NOTHING;

-- 2.13 LIKES
INSERT INTO public.likes (id, post_id, profile_id, created_at, updated_at)
SELECT 
    ml.new_id,
    post.id,
    prof.id,
    ml.created_at,
    ml.updated_at
FROM migration_export.likes ml
JOIN public.posts post ON ml.original_post_uuid = post.public_id
JOIN public.profiles prof ON ml.original_profile_uuid = prof.public_id
ON CONFLICT DO NOTHING;

-- 2.14 STASH
INSERT INTO public.stash (id, product_id, profile_id, restash_id, restash_list_id, restash_post_id, restash_profile_id, created_at, updated_at)
SELECT 
    ms.new_id,
    prod.id,
    prof.id,
    NULL, -- Cannot resolve restash_id easily without UUID in export
    r_list.id,
    r_post.id,
    r_prof.id,
    ms.created_at,
    ms.updated_at
FROM migration_export.stash ms
JOIN public.products prod ON ms.original_product_uuid = prod.public_id
JOIN public.profiles prof ON ms.original_profile_uuid = prof.public_id
LEFT JOIN public.lists r_list ON ms.original_restash_list_uuid = r_list.public_id
LEFT JOIN public.posts r_post ON ms.original_restash_post_uuid = r_post.public_id
LEFT JOIN public.profiles r_prof ON ms.original_restash_profile_uuid = r_prof.public_id
ON CONFLICT DO NOTHING;

-- 2.15 GIVEAWAY ENTRIES
INSERT INTO public.giveaway_entries (id, public_id, profile_id, giveaway_id, won, sent, shipping_notes, created_at, updated_at)
SELECT 
    mge.new_id,
    mge.public_id,
    prof.id,
    g.id,
    mge.won,
    mge.sent,
    mge.shipping_notes,
    mge.created_at,
    mge.updated_at
FROM migration_export.giveaway_entries mge
JOIN public.profiles prof ON mge.original_profile_uuid = prof.public_id
JOIN public.giveaways g ON mge.original_giveaway_uuid = g.public_id
ON CONFLICT DO NOTHING;

-- 2.16 GIVEAWAY ENTRIES MESSAGES
INSERT INTO public.giveaway_entries_messages (id, public_id, profile_id, giveaway_entry_id, message, created_at, updated_at)
SELECT 
    mgem.new_id,
    mgem.public_id,
    prof.id,
    ge.id,
    mgem.message,
    mgem.created_at,
    mgem.updated_at
FROM migration_export.giveaway_entries_messages mgem
JOIN public.profiles prof ON mgem.original_profile_uuid = prof.public_id
JOIN public.giveaway_entries ge ON mgem.original_giveaway_entry_uuid = ge.public_id
ON CONFLICT DO NOTHING;

-- 2.17 SUBSCRIPTIONS LISTS
INSERT INTO public.subscriptions_lists (id, profile_id, list_id, created_at, updated_at)
SELECT 
    msl.new_id,
    prof.id,
    list.id,
    msl.created_at,
    msl.updated_at
FROM migration_export.subscriptions_lists msl
JOIN public.profiles prof ON msl.original_profile_uuid = prof.public_id
JOIN public.lists list ON msl.original_list_uuid = list.public_id
ON CONFLICT DO NOTHING;

-- 2.18 GIVEAWAYS REGIONS
INSERT INTO public.giveaways_regions (id, giveaway_id, region_id)
SELECT 
    mgr.new_id,
    g.id,
    mgr.region_id
FROM migration_export.giveaways_regions mgr
JOIN public.giveaways g ON mgr.original_giveaway_uuid = g.public_id
ON CONFLICT DO NOTHING;

-- Re-enable triggers
SET session_replication_role = DEFAULT;

-- ============================================================================
-- 9. VERIFY UPDATES
-- ============================================================================
SELECT 'profiles_with_avatar' as metric, COUNT(*) FROM public.profiles WHERE avatar_id IS NOT NULL
UNION ALL SELECT 'locations_with_brand', COUNT(*) FROM public.locations WHERE brand_id IS NOT NULL
UNION ALL SELECT 'products_with_category', COUNT(*) FROM public.products WHERE category_id IS NOT NULL
UNION ALL SELECT 'posts_with_profile', COUNT(*) FROM public.posts WHERE profile_id IS NOT NULL
UNION ALL SELECT 'likes_count', COUNT(*) FROM public.likes;
