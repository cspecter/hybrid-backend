-- Fix incorrect volatility for computed column function
-- It was marked IMMUTABLE but queries the database, so it should be STABLE

CREATE OR REPLACE FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") RETURNS integer
    LANGUAGE "sql" STABLE STRICT
    AS $$
    select count(id) from notifications where is_read = false and profile_id = rec.profile_id;
$$;

COMMENT ON FUNCTION "public"."_unread_notification_count"("rec" "public"."notifications") IS '@graphql({"name": "unreadNotificationCount"})';
