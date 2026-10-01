-- Put the winner-email outcome where the person who drew the giveaway will see it.
--
-- The failure notification names the giveaway and the reason but links nowhere, because no
-- screen showed this. Following one up meant querying v_giveaway_email_outcome by hand,
-- which is not a thing to ask of someone running 30 days of giveaways.
--
-- Super admins only. They are who the alert goes to, and a winner's email outcome is
-- operational detail about a particular person rather than something a brand needs about
-- its own giveaway. A non-super-admin gets an empty result, not an error, so the admin list
-- simply shows nothing for them.
create or replace function public.get_giveaway_email_status(p_giveaway_ids integer[])
returns table (
  giveaway_id integer,
  attempts    integer,
  sent        integer,
  failed      integer,
  no_email    integer,
  in_flight   integer,
  never_sent  integer,
  status      text,
  last_at     timestamptz,
  detail      text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return;
  end if;

  return query
  select v.giveaway_id,
         count(*)::int                                                              as attempts,
         count(*) filter (where v.outcome = 'sent')::int                            as sent,
         count(*) filter (where v.outcome = 'failed')::int                           as failed,
         count(*) filter (where v.outcome = 'refused by the function')::int          as no_email,
         count(*) filter (where v.outcome = 'in flight')::int                        as in_flight,
         count(*) filter (where v.outcome = 'never sent')::int                       as never_sent,
         -- One word for the badge. Worst news first: a failure is the thing someone has to
         -- act on, and a giveaway with one sent and one failed email is not "sent".
         case
           when count(*) filter (where v.outcome = 'failed')     > 0 then 'failed'
           when count(*) filter (where v.outcome = 'never sent') > 0 then 'never sent'
           when count(*) filter (where v.outcome = 'in flight')  > 0 then 'sending'
           when count(*) filter (where v.outcome = 'sent')       > 0 then 'sent'
           when count(*) filter (where v.outcome = 'refused by the function') > 0 then 'no email'
           else 'unknown'
         end                                                                        as status,
         max(v.queued_at)                                                           as last_at,
         -- The reason for the worst outcome, which is the one worth reading.
         (array_agg(left(coalesce(v.detail, v.note), 160)
                    order by case v.outcome
                               when 'failed'     then 1
                               when 'never sent' then 2
                               when 'in flight'  then 3
                               when 'sent'       then 4
                               else 5
                             end, v.queued_at desc))[1]                             as detail
  from public.v_giveaway_email_outcome v
  where v.giveaway_id = any(p_giveaway_ids)
  group by v.giveaway_id;
end $$;

comment on function public.get_giveaway_email_status(integer[]) is
  'Winner-email outcome per giveaway for the admin list: counts, a one-word status, and the reason for the worst outcome. Super admins only; anyone else gets no rows.';

revoke all on function public.get_giveaway_email_status(integer[]) from public, anon;
grant execute on function public.get_giveaway_email_status(integer[]) to authenticated;
