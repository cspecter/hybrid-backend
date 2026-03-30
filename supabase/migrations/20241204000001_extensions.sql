-- Migration: Extensions
-- Description: Creates all required PostgreSQL extensions
-- This should run first as other objects depend on these extensions

-- pg_cron for scheduled jobs
CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";

-- pgroonga for full-text search (Japanese, Chinese, etc.)
CREATE EXTENSION IF NOT EXISTS "pgroonga" WITH SCHEMA "extensions";

-- cube for multi-dimensional indexing
CREATE EXTENSION IF NOT EXISTS "cube" WITH SCHEMA "public";

-- earthdistance for geographic distance calculations (depends on cube)
CREATE EXTENSION IF NOT EXISTS "earthdistance" WITH SCHEMA "public";

-- fuzzystrmatch for fuzzy string matching
CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch" WITH SCHEMA "extensions";

-- http for making HTTP requests from within the database
CREATE EXTENSION IF NOT EXISTS "http" WITH SCHEMA "extensions";

-- pg_graphql for GraphQL API
CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

-- pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

-- pg_trgm for trigram matching (fuzzy search)
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "extensions";

-- pgcrypto for cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

-- pgjwt for JWT token handling
CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

-- pgroonga_database extension
CREATE EXTENSION IF NOT EXISTS "pgroonga_database" WITH SCHEMA "extensions";

-- PostGIS for geographic data types and functions
-- Keep in extensions schema for Supabase compatibility
CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";

-- unaccent for removing accents from text
CREATE EXTENSION IF NOT EXISTS "unaccent" WITH SCHEMA "public";

-- uuid-ossp for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
