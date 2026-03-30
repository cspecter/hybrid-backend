-- Migration: Types and Utility Functions
-- Description: Creates all custom types, enums, and utility functions needed by tables

-- ============================================================================
-- COMPOSITE TYPES
-- ============================================================================

CREATE TYPE "public"."t" AS (
    "a" integer,
    "b" "text"
);
ALTER TYPE "public"."t" OWNER TO "postgres";

-- ============================================================================
-- ENUMS
-- ============================================================================

-- Profile types (individual, brand, creator, organization)
CREATE TYPE public.profile_type AS ENUM (
    'individual',    -- Regular user
    'brand',         -- Business/brand account
    'creator',       -- Content creator (may have additional features)
    'organization'   -- Non-profit, government, etc.
);

-- Location types (for generic locations table)
CREATE TYPE public.location_type AS ENUM (
    'dispensary',
    'delivery',
    'manufacturer',
    'distributor',
    'testing_lab',
    'cultivation',
    'retail',
    'pop_up',
    'other'
);

-- Notification categories (for modern notification system)
CREATE TYPE public.notification_category AS ENUM (
    'social',        -- follows, likes, comments
    'activity',      -- posts, mentions, tags
    'promotions',    -- deals, giveaways, marketing
    'system',        -- account, security, updates
    'transactional'  -- orders, confirmations (always sent)
);

-- Notification delivery channels
CREATE TYPE public.notification_channel AS ENUM (
    'in_app',
    'push',
    'email',
    'sms'
);

-- ============================================================================
-- UTILITY FUNCTIONS (must be created before tables that use them as defaults)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.generate_randome_code() 
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
    icode varchar = CAST(FLOOR((RANDOM() * (899999) + 100000)) as varchar);
BEGIN
    RETURN iCode;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_username() 
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
    icount int = 0;
    result varchar;
BEGIN
    result := concat('Hybrid ', icount);
    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_randome_code() TO anon;
GRANT EXECUTE ON FUNCTION public.generate_randome_code() TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_randome_code() TO service_role;

GRANT EXECUTE ON FUNCTION public.generate_username() TO anon;
GRANT EXECUTE ON FUNCTION public.generate_username() TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_username() TO service_role;
