-- Function to get locations nearby
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
    location_type text, -- Changed from public.location_type to text to avoid casting issues
    status text, -- Changed from varchar to text
    is_verified boolean,
    address_line1 text, -- Changed from varchar to text
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
        l.public_id as id,
        l.name,
        l.description,
        l.slug,
        l.location_type::text, -- Cast to text
        l.status::text, -- Cast to text
        l.is_verified,
        l.address_line1::text, -- Cast to text
        l.city,
        l.state,
        extensions.st_distance(
            l.coordinates,
            extensions.st_point(p_lng, p_lat)::extensions.geography
        ) as distance_meters,
        extensions.st_y(l.coordinates::extensions.geometry) as lat,
        extensions.st_x(l.coordinates::extensions.geometry) as lng,
        cf_logo.secure_url as logo_url,
        cf_banner.secure_url as banner_url
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
