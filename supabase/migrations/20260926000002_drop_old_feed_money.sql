-- Remove the one-argument feed_money.
--
-- Adding the ceiling as feed_money(text, numeric default 10000) did not replace
-- feed_money(text) — a different argument list is a different function, so both
-- existed and every call resolved to neither: "function public.feed_money(text) is
-- not unique". The import failed on its first chunk.
--
-- CREATE OR REPLACE only replaces when the signature matches exactly. Adding a
-- defaulted parameter looks like a compatible change and is not.
drop function if exists public.feed_money(text);
