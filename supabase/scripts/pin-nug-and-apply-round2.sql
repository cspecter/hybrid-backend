-- Pin the one handle that must not apply, then write the rest.
--
-- brand 197's handle is 'nug', three characters. It was scored high only during
-- the window when 20261110000001 had dropped the four-character floor, and
-- restoring the floor in 20261110000002 does not undo it: a handle below the
-- floor is excluded from the recompute, so the stale 'high' simply persists.
-- confidence_override is the only thing that holds, because confidence itself is
-- recomputed at the top of every social_discovery_apply().
UPDATE public.social_discovery
   SET confidence_override = 'low',
       note = coalesce(note,'') || ' [held 2026-11-10: three characters, too short for the echo test to mean anything. Scored high only while the length floor was missing; the floor is back but does not revisit rows it excludes.]'
 WHERE subject_type = 'brand' AND subject_id = 197;

-- What this will write, before it writes it.
SELECT count(*) AS profiles_about_to_be_filled
  FROM public.social_discovery d
  JOIN public.profiles p ON p.id = d.subject_id
 WHERE d.subject_type = 'brand'
   AND d.instagram IS NOT NULL
   AND coalesce(d.confidence_override, d.confidence) = 'high'
   AND coalesce(nullif(trim(p.social_links->>'instagram'), ''), '') = '';

SELECT jsonb_pretty(public.social_discovery_apply('brand')) AS result;
