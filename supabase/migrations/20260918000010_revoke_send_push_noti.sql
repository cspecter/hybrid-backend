-- Remove client access to send_push_noti.
--
-- public.send_push_noti(message text, devices json, data_type text, campaign text,
-- app_url text) POSTs to https://onesignal.com with a OneSignal REST API key
-- embedded in the function body. It is SECURITY INVOKER and returns void, so the
-- SECURITY DEFINER sweep in 20260918000003 never covered it, and anon held EXECUTE.
--
-- That meant any holder of the public anon key could call /rpc/send_push_noti and
-- push an arbitrary message, to an arbitrary devices list, with an arbitrary
-- app_url, through this project's OneSignal account.
--
-- Unlike the eight dropped in 20260918000009, this one points at a live third party,
-- so the credential in it is real rather than moot. This migration closes the
-- reachability. It does NOT rotate the key -- that has to happen in the OneSignal
-- dashboard, and it should happen regardless of this change, because the key has
-- been sitting in a function body readable by anyone who could reach the catalog.
--
-- The function itself is kept rather than dropped. Nothing calls it today -- no
-- trigger, cron job, policy, view, constraint, default, index expression or other
-- function, and no reference in hybrid-raskin on any branch -- but OneSignal is a
-- live provider and whether this is wanted server-side is a product decision, not a
-- dead-code question. Revoking is reversible; dropping is the call to make
-- deliberately.
--
-- Revokes from PUBLIC as well as the two named roles. The ACL was
--   {=X/postgres, postgres=X/postgres, anon=X/postgres, authenticated=X/postgres,
--    service_role=X/postgres}
-- and that leading =X is the PUBLIC grant, so revoking anon and authenticated alone
-- would have left anon's access intact through PUBLIC and changed nothing
-- observable. Same trap as the 81-of-82 case in 20260918000003.
--
-- postgres and service_role are re-granted explicitly so the PUBLIC revoke cannot
-- take their access away. There is only one overload.
REVOKE ALL PRIVILEGES ON FUNCTION public.send_push_noti(text, json, text, text, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_noti(text, json, text, text, text)
    TO postgres, service_role;
