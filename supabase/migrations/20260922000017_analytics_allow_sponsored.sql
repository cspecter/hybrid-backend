-- analytics_events constrains BOTH event_type and target_type to a fixed list.
-- Neither 'sponsored_impression'/'sponsored_tap' nor the 'campaign' target were in
-- them, so every sponsored event was rejected at insert — after passing the rate
-- limit, the dedupe and the self-action exclusion, which is exactly the kind of
-- thing reading track_event() alone does not tell you. Found by the first
-- behavioural call, not by inspecting the function.
--
-- Extending the lists rather than dropping them: the whitelist is what stops a
-- client inventing event types and polluting a table every dashboard reads.
alter table public.analytics_events
  drop constraint if exists analytics_events_event_type_check;
alter table public.analytics_events
  add constraint analytics_events_event_type_check
  check (event_type = any (array[
    'post_impression', 'post_view', 'video_watch', 'profile_visit', 'product_view',
    'list_view', 'location_view', 'giveaway_view', 'share', 'link_tap', 'phone_tap',
    'directions_tap', 'website_tap', 'unfollow', 'unlike', 'unstash',
    'referral_visit', 'referral_signup_start',
    'sponsored_impression', 'sponsored_tap'
  ]));

alter table public.analytics_events
  drop constraint if exists analytics_events_target_type_check;
alter table public.analytics_events
  add constraint analytics_events_target_type_check
  check (target_type = any (array[
    'post', 'profile', 'product', 'list', 'location', 'giveaway', 'campaign'
  ]));
