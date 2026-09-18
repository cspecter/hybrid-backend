-- SECURITY CONTAINMENT: remove anon/authenticated access to the CMS tables.
--
-- The public schema is exposed through the Data API, and these 36 tables carry
-- no RLS and no policies, so PostgREST served them to any caller holding only
-- the anon key. Confirmed by request: a curl with the anon key alone returned a
-- row from directus_users. The tables hold password, token, tfa_secret,
-- reset_password_token, email and live session tokens.
--
-- This is the smallest change that closes it: REVOKE ALL on each table from
-- anon and authenticated. Once neither role holds any privilege, PostgREST
-- returns 401/permission denied regardless of RLS, because table privileges are
-- checked before row security.
--
-- Deliberately NOT done here -- each is a real follow-up, none is needed to stop
-- the bleeding:
--   * not moving the tables to another schema
--   * not enabling RLS on them
--   * not touching any app table, policy or grant
--   * not altering default privileges, so a future CMS migration that creates a
--     new table can re-open this. Track separately.
--   * not revoking the matching sequence privileges. Sequences leak only
--     counter values, not row data.
--
-- Safe for the CMS: anon and authenticated are NOLOGIN roles in Supabase. They
-- exist only to be assumed via SET ROLE by the authenticator role that PostgREST
-- connects as. No external client can connect as either one, so no Directus or
-- Payload connection can be using them. Verified against pg_roles
-- (rolcanlogin = false for both) and pg_stat_activity, which shows only
-- authenticator/postgres/supabase_admin connected.
--
-- The 36 table names below were enumerated from the linked database
-- (pg_class.relrowsecurity = false in schema public) on 2026-09-18, not written
-- from memory. All 36 are directus_* or payload_*; no app table is in the set.
-- Supabase's own security advisor independently reports the same 36 under
-- rls_disabled_in_public.
--
-- Each revoke is guarded with to_regclass so this migration is a no-op on a
-- bootstrap where the CMS tables were never created.

DO $$
DECLARE
    t text;
    n integer := 0;
    cms_tables text[] := ARRAY[
        'directus_access',
        'directus_activity',
        'directus_collections',
        'directus_comments',
        'directus_dashboards',
        'directus_extensions',
        'directus_fields',
        'directus_files',
        'directus_flows',
        'directus_folders',
        'directus_migrations',
        'directus_notifications',
        'directus_operations',
        'directus_panels',
        'directus_permissions',
        'directus_policies',
        'directus_presets',
        'directus_relations',
        'directus_revisions',
        'directus_roles',
        'directus_sessions',
        'directus_settings',
        'directus_shares',
        'directus_translations',
        'directus_users',
        'directus_versions',
        'directus_webhooks',
        'payload_kv',
        'payload_locked_documents',
        'payload_locked_documents_rels',
        'payload_media',
        'payload_migrations',
        'payload_preferences',
        'payload_preferences_rels',
        'payload_users',
        'payload_users_sessions'
    ];
BEGIN
    FOREACH t IN ARRAY cms_tables LOOP
        IF to_regclass('public.' || quote_ident(t)) IS NOT NULL THEN
            EXECUTE format(
                'REVOKE ALL PRIVILEGES ON TABLE public.%I FROM anon, authenticated',
                t
            );
            n := n + 1;
        ELSE
            RAISE NOTICE 'skipping %, not present', t;
        END IF;
    END LOOP;
    RAISE NOTICE 'revoked anon/authenticated privileges on % CMS table(s)', n;
END
$$;
