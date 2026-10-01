-- Let someone give us their email address, and nothing else.
--
-- Transactional email works -- a send test on 1 Oct 2026 came back queued -- and has almost
-- nobody to reach: of 3,054 profiles exactly one has an address, because sign-in is phone
-- OTP and the product never asks. A giveaway entry is the one moment a person has a reason
-- to hand one over, since it is how they hear they won.
--
-- A narrow function rather than a client-side update. The RLS policy on profiles already
-- lets a person update their own row, which means it lets them update every column of it;
-- collecting an email address does not need that reach.
create or replace function public.set_my_email(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email   text := lower(trim(coalesce(p_email, '')));
  v_profile integer;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'not signed in');
  end if;

  select id into v_profile from profiles where auth_id = auth.uid() limit 1;
  if v_profile is null then
    return jsonb_build_object('ok', false, 'error', 'no profile');
  end if;

  -- Clearing it is allowed: someone who gave an address can take it back.
  if v_email = '' then
    update profiles set email = null where id = v_profile;
    return jsonb_build_object('ok', true, 'cleared', true);
  end if;

  -- Deliberately permissive. This is a cheap guard against a stray tap, not an attempt to
  -- decide what a valid address is -- that argument is unwinnable and Mailgun settles it
  -- anyway when the first message bounces.
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    return jsonb_build_object('ok', false, 'error', 'that does not look like an email address');
  end if;
  if length(v_email) > 254 then
    return jsonb_build_object('ok', false, 'error', 'that address is too long');
  end if;

  update profiles set email = v_email where id = v_profile;
  return jsonb_build_object('ok', true, 'email', v_email);
end $$;

comment on function public.set_my_email(text) is
  'Set or clear the signed-in person''s email address, and only that column. Returns {ok, email} or {ok:false, error}.';

revoke all on function public.set_my_email(text) from public, anon;
grant execute on function public.set_my_email(text) to authenticated;
