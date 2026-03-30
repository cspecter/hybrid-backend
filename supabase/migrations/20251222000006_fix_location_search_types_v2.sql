-- Drop the function first to ensure a clean slate
DROP FUNCTION IF EXISTS public.get_locations_nearby(double precision, double precision, double precision, integer, integer);

-- Recreate the function with explicit casts
CREATE OR REPLACE FUNCTION public.get_locations_nearby(
    p_lat double precision,
    p_lng double precision,
    p_radius_meters double precision DEFAULT 50000,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE (
    id uuid,
    name text,
    description text,
    slug text,
    location_type text,
    status text,
    is_verified boolean,
    address_line1 text,
    city text,
    state text,
    distance_meters double precision,
    lat double precision,
    lng double precision,
    logo_url text,
    banner_url text
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.public_id,
        l.name::text,
        l.description::text,
        l.slug::text,
        l.location_type::text,
        l.status::text,
        l.is_verified,
        l.address_line1::text,
        l.city::text,
        l.state::text,
        extensions.st_distance(
            l.coordinates,
            extensions.st_point(p_lng, p_lat)::extensions.geography
        )::double precision,
        extensions.st_y(l.coordinates::extensions.geometry)::double precision,
        extensions.st_x(l.coordinates::extensions.geometry)::double precision,
        cf_logo.secure_url::text,
        cf_banner.secure_url::text
    FROM
        public.locations l
    LEFT JOIN
        public.cloud_files cf_logo ON l.logo_id = cf_logo.id
    LEFT JOIN
        public.cloud_files cf_banner ON l.banner_id = cf_banner.id
    WHERE
        extensions.st_dwithin(
            l.coordinates,
            extensions.st_point(p_lng, p_lat)::extensions.geography,
            p_radius_meters
        )
        AND l.status = 'published'
    ORDER BY
        l.coordinates <-> extensions.st_point(p_lng, p_lat)::extensions.geography
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION public.get_locations_nearby TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_locations_nearby TO anon;
GRANT EXECUTE ON FUNCTION public.get_locations_nearby TO service_role;