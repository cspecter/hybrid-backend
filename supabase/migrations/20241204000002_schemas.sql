-- Migration: Schemas
-- Description: Creates all custom schemas and sets up schema ownership

-- Create private schema for internal/sensitive data
CREATE SCHEMA IF NOT EXISTS "private";
ALTER SCHEMA "private" OWNER TO "postgres";

-- Set up public schema ownership
ALTER SCHEMA "public" OWNER TO "postgres";
