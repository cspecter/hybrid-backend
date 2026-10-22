-- Count how many times someone has waved away the "add a photo" prompt.
--
-- Signup required a profile photo before it would let anyone in. That is the
-- most expensive thing to ask of a person standing at a dispensary counter
-- with a queue behind them: a name and a handle are typing, a photo is taking
-- a selfie in front of strangers. The requirement moves to later, where it
-- can be asked three times and then insisted on.
--
-- A counter on the profile rather than in localStorage, because "three times"
-- has to mean three times for the person, not three times on this device.
-- Local storage resets when a browser clears site data, when they reinstall,
-- and whenever they pick up a different phone — so the prompt would never
-- reach the point of being required for anyone who did any of those, and
-- would demand a photo on day one from anyone who did not.
alter table public.profiles
  add column if not exists avatar_prompt_dismissals integer not null default 0;

comment on column public.profiles.avatar_prompt_dismissals is
  'Times this person has dismissed the add-a-photo prompt. At 3 the prompt '
  'stops offering Later. Reset to 0 if they upload one and remove it again.';
