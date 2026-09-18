-- Recover the notification type of the 21,001 legacy rows from their title text.
--
-- Those rows all carry type_id = 1, an id notification_types does not contain --
-- see 20260918000021, which marked notifications_type_id_fkey NOT VALID to stop
-- the catalog claiming otherwise. The import that created them recorded no type;
-- the only surviving evidence of what each one was is the wording of its title,
-- which the legacy sender composed per type and which is therefore a reliable
-- discriminator. Where a title shape is ambiguous between a product and a
-- giveaway ("... is dropping tomorrow at 4:20 PM"), related_type settles it.
--
-- Rows are matched against the existing vocabulary only. No new notification_types
-- row is invented, and nothing outside type_id is written.
--
-- Measured on production in BEGIN/ROLLBACK, this retypes 20,852 of 21,001:
--
--   new_post_from_following  5,380     product_dropping_7days    127
--   post_liked               4,591     list_items_added           98
--   new_follower             3,756     giveaway_won               84
--   new_list_from_following  1,993     upgraded_to_creator        69
--   restash_from_post        1,480     giveaway_drawing_1day      58
--   restash_from_profile     1,301     employee_request            8
--   product_tagged_in_post     766     product_stashed             6
--   giveaway_entered           354     budtender_notification      3
--   product_dropping_1day      304     restash_from_list           1
--   product_dropped            276
--   giveaway_drawing_1hour     197
--
-- The remaining 149 keep type_id = 1 and are listed here so the next person does
-- not have to rediscover them. They are not unmatched by oversight; the existing
-- vocabulary has nowhere to put them:
--
--   ~85  self-action echoes -- "You followed Raskin", "You created list X's list",
--        "You added 3 new products to My first stashlist". Every code in
--        notification_types describes something another actor or the system did.
--        There is no code for telling someone what they themselves just did, and
--        inventing one decides what these look like in Alerts.
--    48  placeholder titles -- 43 rows titled "1", four titled "1" with no
--        related_type, one titled "Notification". No recoverable information.
--    29  giveaway teasers -- "Are you a potential winner? X ends on ...",
--        "X is coming soon on ...", "Did you win? Check on the draw". Clearly
--        drawing reminders, but which of giveaway_drawing_3days / _1day / _1hour
--        or new_giveaway_from_following is a judgement about what the user was
--        being told, not something the title settles.
--
-- So notifications_type_id_fkey stays NOT VALID after this migration. Once those
-- 149 have a home, ALTER TABLE public.notifications VALIDATE CONSTRAINT
-- notifications_type_id_fkey finishes the job.
--
-- On side effects: notifications carries trg_set_notification_urls, a BEFORE
-- INSERT OR UPDATE trigger on every column that backfills image_url and
-- action_url when they are NULL. It therefore fires on this UPDATE. Rehearsed
-- against production, it changes neither column on any of the 20,852 rows --
-- the ones it could fill are already filled, and the rest have no source to fill
-- from. This migration writes type_id and nothing else.

WITH mapped AS (
    SELECT id,
        CASE
          WHEN title ~ 'created a new post'                          THEN 24
          WHEN title ~ 'liked your post'                             THEN 12
          WHEN title ~ 'is now following you'                        THEN 11
          WHEN title ~ 'created a new list'                          THEN 20
          WHEN title ~ 'restashed .* from your post'                 THEN 18
          WHEN title ~ 'restashed .* from your list'                 THEN 16
          WHEN title ~ 'restashed .* from your (profile|account)'    THEN 17
          WHEN title ~ 'products restashed from your account'        THEN 17
          WHEN title ~ 'items added to'                              THEN 21
          WHEN title ~ 'new products added'                          THEN 21
          WHEN title ~ 'users tagged .* in their posts'              THEN 28
          WHEN title ~* 'approved creator|authorized hybrid creator' THEN 60
          WHEN title ~* 'you won'                                    THEN 40
          WHEN title ~* 'you entered to win'                         THEN 36
          WHEN title ~* 'ends soon|min left|hours left|hour left'    THEN 39
          WHEN title ~* 'subscribed to your list'                    THEN 22
          WHEN title ~* 'stashed your'                               THEN 15
          WHEN title ~* 'you liked .*post'                           THEN 12
          WHEN title ~* 'requesting to join your'                    THEN 54
          WHEN title ~* 'added as a budtender'                       THEN 57
          WHEN title ~* 'is now available' AND related_type = 'product'  THEN 32
          WHEN title ~* 'dropping in one week' AND related_type = 'product' THEN 30
          WHEN title ~* 'dropping (in one day|tomorrow)' AND related_type = 'product' THEN 31
          WHEN title ~* 'dropping (in one day|tomorrow)' AND related_type = 'giveaway' THEN 38
          ELSE NULL
        END AS tid
    FROM public.notifications
    WHERE type_id = 1
)
UPDATE public.notifications n
   SET type_id = mapped.tid
  FROM mapped
 WHERE n.id = mapped.id
   AND mapped.tid IS NOT NULL;
