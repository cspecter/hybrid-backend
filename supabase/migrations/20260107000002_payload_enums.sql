-- Migration to rename PostgreSQL Enums to match PayloadCMS naming convention (enum_<collection>_<field>)
-- And create missing Enums required by Payload

-- 1. Rename 'profile_type' to 'enum_profiles_profile_type'
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'profile_type') THEN
        ALTER TYPE "public"."profile_type" RENAME TO "enum_profiles_profile_type";
    END IF;
END $$;

-- 2. Rename 'location_type' to 'enum_locations_location_type'
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'location_type') THEN
        ALTER TYPE "public"."location_type" RENAME TO "enum_locations_location_type";
    END IF;
END $$;

-- 3. Create 'enum_profiles_status' if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'enum_profiles_status') THEN
        CREATE TYPE "public"."enum_profiles_status" AS ENUM('active', 'suspended', 'deleted', 'published');
    END IF;
END $$;

-- 4. Create 'enum_products_status' if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'enum_products_status') THEN
        CREATE TYPE "public"."enum_products_status" AS ENUM('draft', 'published', 'archived');
    END IF;
END $$;

-- 5. Create 'enum_locations_status' if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'enum_locations_status') THEN
        CREATE TYPE "public"."enum_locations_status" AS ENUM('draft', 'published', 'archived', 'temporarily_closed');
    END IF;
END $$;
