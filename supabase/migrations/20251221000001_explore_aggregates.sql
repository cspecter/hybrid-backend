-- RPC for Top Creators
CREATE OR REPLACE FUNCTION public.get_top_creators(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE sql
STABLE
AS $$
    SELECT p.* 
    FROM public.profiles p
    LEFT JOIN (
        SELECT profile_id, SUM(like_count) as total_likes
        FROM public.posts
        GROUP BY profile_id
    ) post_likes ON p.id = post_likes.profile_id
    WHERE p.profile_type = 'creator' 
    ORDER BY (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC 
    LIMIT limit_count;
$$;

-- RPC for Top Budtenders
CREATE OR REPLACE FUNCTION public.get_top_budtenders(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE sql
STABLE
AS $$
    SELECT p.* 
    FROM public.profiles p
    JOIN public.location_employees le ON p.id = le.profile_id
    LEFT JOIN (
        SELECT profile_id, SUM(like_count) as total_likes
        FROM public.posts
        GROUP BY profile_id
    ) post_likes ON p.id = post_likes.profile_id
    WHERE le.role = 'budtender'
    GROUP BY p.id, post_likes.total_likes
    ORDER BY (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC 
    LIMIT limit_count;
$$;

-- RPC for New Releases
CREATE OR REPLACE FUNCTION public.get_new_releases(limit_count integer DEFAULT 10)
RETURNS SETOF public.products
LANGUAGE sql
STABLE
AS $$
    SELECT * 
    FROM public.products 
    WHERE release_date > (now() - interval '1 month')
    ORDER BY release_date ASC 
    LIMIT limit_count;
$$;

-- RPC for Top Posts
CREATE OR REPLACE FUNCTION public.get_top_posts(limit_count integer DEFAULT 10)
RETURNS SETOF public.posts
LANGUAGE sql
STABLE
AS $$
    SELECT * 
    FROM public.posts 
    WHERE created_at > (now() - interval '1 month')
    ORDER BY like_count DESC 
    LIMIT limit_count;
$$;

-- RPC for Popular Brands
CREATE OR REPLACE FUNCTION public.get_popular_brands(limit_count integer DEFAULT 10)
RETURNS SETOF public.profiles
LANGUAGE sql
STABLE
AS $$
    SELECT p.* 
    FROM public.profiles p
    LEFT JOIN (
        SELECT profile_id, SUM(like_count) as total_likes
        FROM public.posts
        GROUP BY profile_id
    ) post_likes ON p.id = post_likes.profile_id
    WHERE p.profile_type = 'brand'
    ORDER BY (p.follower_count + COALESCE(post_likes.total_likes, 0)) DESC 
    LIMIT limit_count;
$$;
