-- Close the three public tables that anonymous callers could actually reach,
-- and switch RLS on for the rest of the public schema.
--
-- Supabase's advisor flagged 39 tables in public with RLS disabled and led with
-- directus_users and directus_sessions. Those are the ones that were never at
-- risk: no grant exists on them for anon or authenticated, so PostgREST could
-- not read them whatever the RLS flag said. Tested as anon, they answer
-- "permission denied for table directus_users".
--
-- Three tables were genuinely open. anon held SELECT, INSERT, UPDATE and DELETE
-- on all three, and RLS was off, so anyone holding the anon key that ships in
-- the app could read every row -- and empty the table:
--
--   content_submissions  39 rows, live (newest 2026-11-09), carries source_url,
--                        posted_by, submitted_by, media and raw_caption
--   intake_bundles        3 rows, carries chat_id and submitter_profile_id
--   brand_aliases         0 rows, unused by any code, view or function
--
-- content_submissions already had a policy, "authenticated read submissions",
-- written by someone and never switched on, because ENABLE ROW LEVEL SECURITY
-- was never run. A policy on a table with RLS disabled does nothing at all.
-- That policy is kept as written: enabling RLS is what finally makes it mean
-- something, and it tightens reads from anyone to signed-in callers only.
--
-- Writers are unaffected. The service that fills these tables uses the
-- service-role key, and both service_role and the postgres owner bypass RLS.

-- 1. The three that were reachable.

alter table public.content_submissions enable row level security;
alter table public.intake_bundles      enable row level security;
alter table public.brand_aliases       enable row level security;

-- Belt and braces: with no grant, anon cannot reach the table even if a
-- permissive policy is ever added by accident.
revoke all on public.content_submissions from anon;
revoke all on public.intake_bundles      from anon;
revoke all on public.brand_aliases       from anon;

-- authenticated keeps only the read that the existing policy describes.
revoke insert, update, delete on public.content_submissions from authenticated;
revoke all                    on public.intake_bundles      from authenticated;
revoke all                    on public.brand_aliases       from authenticated;

-- intake_bundles and brand_aliases get no policy, so with RLS on they are
-- reachable only by the service role and the owner. Nothing in the app or the
-- Edge Functions reads either one. If an admin screen turns out to need
-- intake_bundles, this is the line that restores what authenticated could see
-- before today, and it should be added deliberately rather than left implicit:
--
--   create policy "Signed-in callers can read intake bundles"
--       on public.intake_bundles as permissive for select to authenticated
--       using (true);

-- 2. The dormant CMS tables. No grants exist on these for anon or
-- authenticated, so this changes no behaviour; it closes the advisor finding
-- and means a future grant cannot quietly open them. Directus has had no
-- activity since 2026-01-28.
alter table public.directus_access enable row level security;
alter table public.directus_activity enable row level security;
alter table public.directus_collections enable row level security;
alter table public.directus_comments enable row level security;
alter table public.directus_dashboards enable row level security;
alter table public.directus_extensions enable row level security;
alter table public.directus_fields enable row level security;
alter table public.directus_files enable row level security;
alter table public.directus_flows enable row level security;
alter table public.directus_folders enable row level security;
alter table public.directus_migrations enable row level security;
alter table public.directus_notifications enable row level security;
alter table public.directus_operations enable row level security;
alter table public.directus_panels enable row level security;
alter table public.directus_permissions enable row level security;
alter table public.directus_policies enable row level security;
alter table public.directus_presets enable row level security;
alter table public.directus_relations enable row level security;
alter table public.directus_revisions enable row level security;
alter table public.directus_roles enable row level security;
alter table public.directus_sessions enable row level security;
alter table public.directus_settings enable row level security;
alter table public.directus_shares enable row level security;
alter table public.directus_translations enable row level security;
alter table public.directus_users enable row level security;
alter table public.directus_versions enable row level security;
alter table public.directus_webhooks enable row level security;
alter table public.payload_kv enable row level security;
alter table public.payload_locked_documents enable row level security;
alter table public.payload_locked_documents_rels enable row level security;
alter table public.payload_media enable row level security;
alter table public.payload_migrations enable row level security;
alter table public.payload_preferences enable row level security;
alter table public.payload_preferences_rels enable row level security;
alter table public.payload_users enable row level security;
alter table public.payload_users_sessions enable row level security;

-- 3. Prove it: anon must see nothing, and nothing in public may still be open.
do $$
declare n bigint; blocked boolean := false;
begin
  set local role anon;
  begin
    execute 'select count(*) from public.content_submissions' into n;
  exception when insufficient_privilege then blocked := true;
  end;
  reset role;
  if not blocked and n > 0 then
    raise exception 'content_submissions is still readable by anon (% rows)', n;
  end if;
end $$;

do $$
declare open_tables text;
begin
  select string_agg(c.relname, ', ')
    into open_tables
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if open_tables is not null then
    raise exception 'tables still without RLS: %', open_tables;
  end if;
end $$;
