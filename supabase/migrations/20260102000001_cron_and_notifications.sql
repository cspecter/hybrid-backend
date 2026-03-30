-- NOTIFICATION SYSTEM COMPLETION
-- 1. Add missing notification types (Comments, Replies, Likes)
-- 2. Add triggers for comments and comment likes
-- 3. Add cleanup function
-- 4. Setup Cron Jobs
-- ============================================================================

-- 1. Add missing notification types
INSERT INTO public.notification_types (
    code, name, category, title_template, body_template, 
    action_url_template, priority, is_groupable, group_key,
    aggregation_window, max_per_window, auto_expire_after
) VALUES
    ('post_commented', 'New Comment', 'social',
     '{actor_name} commented on your post',
     '{actor_name} commented: "{comment_preview}"',
     '/post/{post_id}', 5, true, 'post_commented:{post_id}',
     '1 hour', 10, '3 days'),

    ('comment_reply', 'New Reply', 'social',
     '{actor_name} replied to your comment',
     '{actor_name} replied: "{comment_preview}"',
     '/post/{post_id}', 5, true, 'comment_reply:{post_id}',
     '1 hour', 10, '3 days'),

    ('comment_liked', 'Comment Liked', 'social',
     '{actor_name} liked your comment',
     '{actor_name} liked your comment on a post',
     '/post/{post_id}', 6, true, 'comment_liked:{comment_id}',
     '1 hour', 50, '3 days')
ON CONFLICT (code) DO NOTHING;

-- 2. Trigger for New Comments / Replies
CREATE OR REPLACE FUNCTION public.fn_notify_on_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post_owner_id integer;
    v_parent_comment_owner_id integer;
    v_comment_preview text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Truncate comment for preview
        v_comment_preview := substring(NEW.message from 1 for 50);
        if length(NEW.message) > 50 then
            v_comment_preview := v_comment_preview || '...';
        end if;

        -- 1. Notify Post Owner (if not self)
        SELECT profile_id INTO v_post_owner_id FROM public.posts WHERE id = NEW.post_id;
        
        IF v_post_owner_id != NEW.profile_id THEN
            PERFORM public.send_notification(
                v_post_owner_id,
                'post_commented',
                NEW.profile_id,
                'post',
                NEW.post_id,
                jsonb_build_object(
                    'comment_preview', v_comment_preview,
                    'comment_id', NEW.id
                )
            );
        END IF;

        -- 2. Notify Parent Comment Owner (if reply and not self)
        IF NEW.parent_id IS NOT NULL THEN
            SELECT profile_id INTO v_parent_comment_owner_id FROM public.post_comments WHERE id = NEW.parent_id;
            
            -- Don't notify if replying to self, or if parent owner is same as post owner (already notified above, 
            -- though usually we want distinct notifications for reply vs post comment. 
            -- Let's notify even if same person, but maybe different type? 
            -- Actually, if I reply to my own post, I don't get notified.
            -- If someone replies to my comment on my post, I get a reply notification.
            -- If someone comments on my post, I get a comment notification.
            
            IF v_parent_comment_owner_id != NEW.profile_id AND v_parent_comment_owner_id != v_post_owner_id THEN
                PERFORM public.send_notification(
                    v_parent_comment_owner_id,
                    'comment_reply',
                    NEW.profile_id,
                    'post',
                    NEW.post_id, -- Link to the post
                    jsonb_build_object(
                        'comment_preview', v_comment_preview,
                        'comment_id', NEW.id,
                        'parent_id', NEW.parent_id
                    )
                );
            ELSIF v_parent_comment_owner_id != NEW.profile_id AND v_parent_comment_owner_id = v_post_owner_id THEN
                 -- If post owner is also parent comment owner, they get a reply notification INSTEAD of comment notification?
                 -- Or both? The 'post_commented' logic above runs regardless.
                 -- To avoid double notification for the post owner who is also the parent commenter:
                 -- We could check logic. But 'post_commented' and 'comment_reply' are different.
                 -- Let's send 'comment_reply' as it is more specific.
                 -- But we already sent 'post_commented'.
                 -- Ideally we shouldn't send 'post_commented' if it's a reply to the post owner.
                 NULL; -- Already handled by post_commented, or maybe we prefer reply?
                 -- Let's keep it simple: Post owner gets 'post_commented'. 
                 -- If it's a reply to someone else, that person gets 'comment_reply'.
            END IF;
            
            -- Correction: If I reply to a comment by User B on User A's post.
            -- User A gets 'post_commented'.
            -- User B gets 'comment_reply'.
            -- This seems correct.
            
            -- What if User A replies to User B on User A's post?
            -- User A (self) -> No notification.
            -- User B -> 'comment_reply'.
            
            -- What if User B replies to User A on User A's post?
            -- User A gets 'post_commented' (from above).
            -- User A is parent owner.
            -- We should probably suppress 'post_commented' if it is a reply to the post owner, and send 'comment_reply' instead?
            -- Or just let 'post_commented' cover it.
            -- Let's stick to: Post owner always gets 'post_commented' for any comment on their post.
            -- Parent comment owner gets 'comment_reply' (unless they are the post owner, to avoid double ping).
        END IF;

        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_comment ON public.post_comments;
CREATE TRIGGER trg_notify_on_comment
    AFTER INSERT ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_notify_on_comment();

-- 3. Trigger for Comment Likes
CREATE OR REPLACE FUNCTION public.fn_notify_on_comment_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_comment_owner_id integer;
    v_post_id integer;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT profile_id, post_id INTO v_comment_owner_id, v_post_id 
        FROM public.post_comments WHERE id = NEW.comment_id;
        
        IF v_comment_owner_id != NEW.profile_id THEN
            PERFORM public.send_notification(
                v_comment_owner_id,
                'comment_liked',
                NEW.profile_id,
                'post', -- Related type is post so clicking goes to the post
                v_post_id,
                jsonb_build_object(
                    'comment_id', NEW.comment_id
                )
            );
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_comment_like ON public.comment_likes;
CREATE TRIGGER trg_notify_on_comment_like
    AFTER INSERT ON public.comment_likes
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_notify_on_comment_like();

-- 4. Cleanup Function (replaces logic in cron-notifications edge function)
CREATE OR REPLACE FUNCTION public.cleanup_notifications()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Clean up old expired notifications (older than 30 days)
    DELETE FROM public.notifications 
    WHERE expires_at < (now() - interval '30 days')
    AND expires_at IS NOT NULL;
    
    -- Clean up old sent scheduled notifications (older than 7 days)
    DELETE FROM public.scheduled_notifications
    WHERE status = 'sent'
    AND sent_at < (now() - interval '7 days');
    
    -- Clean up old notification aggregates (older than 7 days with no activity)
    DELETE FROM public.notification_aggregates
    WHERE last_updated_at < (now() - interval '7 days');
END;
$$;

-- 5. Setup Cron Jobs
-- Enable pg_cron if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule scheduled notifications processing (every 5 minutes)
-- This runs the SQL function directly, more efficient than calling edge function
SELECT cron.schedule(
    'process_scheduled_notifications',
    '*/5 * * * *',
    $$SELECT public.process_scheduled_notifications()$$
);

-- Schedule cleanup (daily at 3am)
SELECT cron.schedule(
    'cleanup_notifications',
    '0 3 * * *',
    $$SELECT public.cleanup_notifications()$$
);

-- Schedule Push Sender (every 1 minute)
-- NOTE: You must replace PROJECT_REF and ANON_KEY with your actual values
-- or configure this via the Supabase Dashboard if you prefer.
-- We use a placeholder here.
/*
SELECT cron.schedule(
    'invoke_push_sender',
    '* * * * *',
    $$
    SELECT net.http_post(
        url:='https://PROJECT_REF.supabase.co/functions/v1/push-sender',
        headers:='{"Content-Type": "application/json", "Authorization": "Bearer ANON_KEY"}'::jsonb,
        body:='{}'::jsonb
    )
    $$
);
*/
-- Uncomment and update the above block to enable push sender scheduling via SQL.
-- Alternatively, use the Supabase Dashboard to create this cron job.

