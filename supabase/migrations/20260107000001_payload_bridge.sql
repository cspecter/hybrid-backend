-- Bridge migration for PayloadCMS compatibility

-- Add required Upload fields to cloud_files
ALTER TABLE "public"."cloud_files" ADD COLUMN IF NOT EXISTS "filename" text;
ALTER TABLE "public"."cloud_files" ADD COLUMN IF NOT EXISTS "mimeType" text;
ALTER TABLE "public"."cloud_files" ADD COLUMN IF NOT EXISTS "filesize" numeric;

-- Ensure created_at/updated_at are available if not present (they are present in core_tables, but safe to check)
-- No action needed for existing tables as they have manage_timestamps trigger and columns.
