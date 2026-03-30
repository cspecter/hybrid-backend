-- Notification System Improvements
-- Enhanced aggregation, rich related data, scheduled notifications, and batch push support
-- Updated: All foreign keys reference integer PKs with public_id UUIDs

-- ============================================================================
-- DROP OLD NOTIFICATION TYPES DATA (we'll re-insert with better structure)
-- ============================================================================

TRUNCATE public.notification_types CASCADE;

-- ============================================================================
-- ENHANCED NOTIFICATION TYPES
-- ============================================================================

-- Add new columns to notification_types for better control
ALTER TABLE public.notification_types 
    ADD COLUMN IF NOT EXISTS aggregation_window interval DEFAULT '1 hour',
    ADD COLUMN IF NOT EXISTS max_per_window integer DEFAULT 1,
    ADD COLUMN IF NOT EXISTS cooldown_period interval,
    ADD COLUMN IF NOT EXISTS requires_action boolean DEFAULT false,
    ADD COLUMN IF NOT EXISTS auto_expire_after interval,
    ADD COLUMN IF NOT EXISTS sound_name text DEFAULT 'default',
    ADD COLUMN IF NOT EXISTS badge_increment integer DEFAULT 1;

-- ============================================================================
-- SCHEDULED NOTIFICATIONS TABLE (for future notifications)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.scheduled_notifications (
    id integer NOT NULL,
    public_id uuid NOT NULL DEFAULT gen_random_uuid(),
    
    -- Target
    profile_id integer REFERENCES public.profiles(id) ON DELETE CASCADE,
    
    -- Notification details
    type_code text NOT NULL,
    
    -- Related entities (polymorphic)
    actor_id integer REFERENCES public.profiles(id) ON DELETE SET NULL,
    related_type text, -- 'product', 'giveaway', 'post', 'deal', 'list', 'profile'
    related_id integer,
    
    -- Extra data for template rendering
    extra_data jsonb DEFAULT '{}',
    
    -- Scheduling
    scheduled_for timestamptz NOT NULL,
    
    -- Status
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'cancelled', 'failed')),
    sent_at timestamptz,
    error_message text,
    
    -- Deduplication
    idempotency_key text UNIQUE,
    
    -- Timestamps
    created_at timestamptz DEFAULT now(),
    
    -- Constraints
    CONSTRAINT scheduled_notifications_pkey PRIMARY KEY (id),
    CONSTRAINT scheduled_notifications_public_id_key UNIQUE (public_id),
    CONSTRAINT scheduled_notifications_future CHECK (scheduled_for > created_at)
);

ALTER TABLE public.scheduled_notifications OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.scheduled_notifications_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.scheduled_notifications_id_seq OWNER TO postgres;
ALTER SEQUENCE public.scheduled_notifications_id_seq OWNED BY public.scheduled_notifications.id;
ALTER TABLE ONLY public.scheduled_notifications ALTER COLUMN id SET DEFAULT nextval('public.scheduled_notifications_id_seq'::regclass);

CREATE INDEX idx_scheduled_notifications_public_id ON public.scheduled_notifications(public_id);
CREATE INDEX idx_scheduled_notifications_pending 
    ON public.scheduled_notifications(scheduled_for) 
    WHERE status = 'pending';

CREATE INDEX idx_scheduled_notifications_profile 
    ON public.scheduled_notifications(profile_id, status);

-- ============================================================================
-- NOTIFICATION AGGREGATES TABLE (for grouping similar notifications)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.notification_aggregates (
    id integer NOT NULL,
    public_id uuid NOT NULL DEFAULT gen_random_uuid(),
    
    -- Target user
    profile_id integer NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    
    -- Grouping key
    aggregate_key text NOT NULL, -- e.g., "post_liked:{post_id}" or "new_follower"
    type_code text NOT NULL,
    
    -- The "representative" notification (shown to user)
    notification_id integer REFERENCES public.notifications(id) ON DELETE SET NULL,
    
    -- Aggregation data
    count integer DEFAULT 1,
    actor_ids integer[] DEFAULT '{}', -- First N actors for "Alice, Bob, and 3 others"
    max_display_actors integer DEFAULT 3,
    
    -- Related entity
    related_type text,
    related_id integer,
    
    -- Window tracking
    window_start timestamptz DEFAULT now(),
    window_end timestamptz,
    last_updated_at timestamptz DEFAULT now(),
    
    -- Has user seen the aggregate?
    is_seen boolean DEFAULT false,
    seen_at timestamptz,
    
    CONSTRAINT notification_aggregates_pkey PRIMARY KEY (id),
    CONSTRAINT notification_aggregates_public_id_key UNIQUE (public_id),
    UNIQUE(profile_id, aggregate_key)
);

ALTER TABLE public.notification_aggregates OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.notification_aggregates_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.notification_aggregates_id_seq OWNER TO postgres;
ALTER SEQUENCE public.notification_aggregates_id_seq OWNED BY public.notification_aggregates.id;
ALTER TABLE ONLY public.notification_aggregates ALTER COLUMN id SET DEFAULT nextval('public.notification_aggregates_id_seq'::regclass);

CREATE INDEX idx_notification_aggregates_public_id ON public.notification_aggregates(public_id);
CREATE INDEX idx_notification_aggregates_profile 
    ON public.notification_aggregates(profile_id, is_seen, last_updated_at DESC);

-- ============================================================================
-- ENHANCED NOTIFICATIONS TABLE
-- ============================================================================

-- Add columns for better related data handling
ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS aggregate_id integer REFERENCES public.notification_aggregates(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS scheduled_notification_id integer REFERENCES public.scheduled_notifications(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS priority integer DEFAULT 5,
    ADD COLUMN IF NOT EXISTS is_aggregated boolean DEFAULT false,
    ADD COLUMN IF NOT EXISTS collapsed_count integer DEFAULT 0;

-- Add related entity columns for direct lookups
ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS post_id integer,
    ADD COLUMN IF NOT EXISTS product_id integer,
    ADD COLUMN IF NOT EXISTS giveaway_id integer,
    ADD COLUMN IF NOT EXISTS deal_id integer,
    ADD COLUMN IF NOT EXISTS list_id integer,
    ADD COLUMN IF NOT EXISTS location_id integer;

-- Create indexes for related lookups
CREATE INDEX IF NOT EXISTS idx_notifications_post ON public.notifications(post_id) WHERE post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_product ON public.notifications(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_giveaway ON public.notifications(giveaway_id) WHERE giveaway_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_deal ON public.notifications(deal_id) WHERE deal_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_aggregate ON public.notifications(aggregate_id) WHERE aggregate_id IS NOT NULL;

-- ============================================================================
-- ENHANCED PUSH QUEUE FOR BATCHING
-- ============================================================================

-- Add columns for better batch processing
ALTER TABLE public.push_queue
    ADD COLUMN IF NOT EXISTS priority integer DEFAULT 5,
    ADD COLUMN IF NOT EXISTS batch_id integer,
    ADD COLUMN IF NOT EXISTS provider text DEFAULT 'onesignal',
    ADD COLUMN IF NOT EXISTS provider_message_id text,
    ADD COLUMN IF NOT EXISTS retry_after timestamptz,
    ADD COLUMN IF NOT EXISTS ttl_seconds integer DEFAULT 86400; -- 24 hours default

-- Push batches table for tracking batch sends
CREATE TABLE IF NOT EXISTS public.push_batches (
    id integer NOT NULL,
    public_id uuid NOT NULL DEFAULT gen_random_uuid(),
    
    -- Batch info
    provider text DEFAULT 'onesignal',
    message_count integer DEFAULT 0,
    
    -- Status tracking
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'partial', 'failed')),
    sent_count integer DEFAULT 0,
    failed_count integer DEFAULT 0,
    
    -- Provider response
    provider_batch_id text,
    provider_response jsonb,
    
    -- Timing
    started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz DEFAULT now(),
    
    CONSTRAINT push_batches_pkey PRIMARY KEY (id),
    CONSTRAINT push_batches_public_id_key UNIQUE (public_id)
);

ALTER TABLE public.push_batches OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.push_batches_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.push_batches_id_seq OWNER TO postgres;
ALTER SEQUENCE public.push_batches_id_seq OWNED BY public.push_batches.id;
ALTER TABLE ONLY public.push_batches ALTER COLUMN id SET DEFAULT nextval('public.push_batches_id_seq'::regclass);

CREATE INDEX idx_push_batches_public_id ON public.push_batches(public_id);
CREATE INDEX idx_push_queue_batch ON public.push_queue(batch_id) WHERE batch_id IS NOT NULL;
CREATE INDEX idx_push_queue_priority ON public.push_queue(priority, send_at) WHERE status = 'pending';

-- ============================================================================
-- INSERT ALL NOTIFICATION TYPES
-- ============================================================================

INSERT INTO public.notification_types (
    code, name, category, title_template, body_template, 
    action_url_template, priority, is_groupable, group_key,
    aggregation_window, max_per_window, auto_expire_after
) VALUES
    -- =========================================================================
    -- SOCIAL NOTIFICATIONS (Follows, Likes, Mentions)
    -- =========================================================================
    ('new_follower', 'New Follower', 'social', 
     '{actor_name} followed you', 
     '{actor_name} started following you',
     '/profile/{actor_id}', 5, true, 'new_follower',
     '1 hour', 10, '7 days'),
    
    ('post_liked', 'Post Liked', 'social',
     '{actor_name} liked your post',
     '{actor_name} liked your post',
     '/post/{post_id}', 6, true, 'post_liked:{post_id}',
     '1 hour', 50, '3 days'),
    
    ('mentioned_in_post', 'Mentioned in Post', 'social',
     '{actor_name} mentioned you',
     '{actor_name} mentioned you in a post',
     '/post/{post_id}', 4, true, 'mentioned:{post_id}',
     '1 hour', 10, '3 days'),
    
    ('tagged_in_post', 'Tagged in Post', 'social',
     '{actor_name} tagged you',
     '{actor_name} tagged you in a post',
     '/post/{post_id}', 4, true, 'tagged:{post_id}',
     '1 hour', 10, '3 days'),
    
    -- =========================================================================
    -- STASH/RESTASH NOTIFICATIONS
    -- =========================================================================
    ('product_stashed', 'Product Stashed', 'social',
     '{actor_name} stashed your product',
     '{actor_name} added {product_name} to their stash',
     '/product/{product_id}', 6, true, 'product_stashed:{product_id}',
     '1 hour', 20, '3 days'),
    
    ('restash_from_list', 'Restash From List', 'social',
     '{actor_name} restashed from your list',
     '{actor_name} restashed {product_name} from your list "{list_name}"',
     '/list/{list_id}', 6, true, 'restash_list:{list_id}',
     '1 hour', 20, '3 days'),
    
    ('restash_from_profile', 'Restash From Profile', 'social',
     '{actor_name} restashed from your stash',
     '{actor_name} restashed {product_name} from your stash',
     '/profile/{profile_id}/stash', 6, true, 'restash_profile',
     '1 hour', 20, '3 days'),
    
    ('restash_from_post', 'Restash From Post', 'social',
     '{actor_name} restashed from your post',
     '{actor_name} restashed {product_name} from your post',
     '/post/{post_id}', 6, true, 'restash_post:{post_id}',
     '1 hour', 20, '3 days'),
    
    ('restash_count_milestone', 'Restash Milestone', 'social',
     'Your stash is growing! 🌱',
     'You now have {count} restashes on your products',
     '/profile/stash', 7, false, NULL,
     '24 hours', 1, '7 days'),
    
    -- =========================================================================
    -- LIST NOTIFICATIONS
    -- =========================================================================
    ('new_list_from_following', 'New List', 'activity',
     '{actor_name} created a new list',
     '{actor_name} created "{list_name}"',
     '/list/{list_id}', 7, true, 'new_lists',
     '4 hours', 5, '3 days'),
    
    ('list_items_added', 'List Updated', 'activity',
     '{actor_name} added to a list',
     '{actor_name} added {count} new items to "{list_name}"',
     '/list/{list_id}', 7, true, 'list_items:{list_id}',
     '4 hours', 3, '3 days'),
    
    ('list_subscribed', 'New List Subscriber', 'social',
     '{actor_name} subscribed to your list',
     '{actor_name} subscribed to "{list_name}"',
     '/list/{list_id}', 6, true, 'list_subscribed:{list_id}',
     '1 hour', 20, '3 days'),
    
    ('subscribed_list_updated', 'Subscribed List Updated', 'activity',
     '"{list_name}" was updated',
     '{actor_name} added new products to "{list_name}"',
     '/list/{list_id}', 7, true, 'sub_list_updated:{list_id}',
     '4 hours', 3, '3 days'),
    
    -- =========================================================================
    -- POST NOTIFICATIONS
    -- =========================================================================
    ('new_post_from_following', 'New Post', 'activity',
     '{actor_name} posted something new',
     '{actor_name} shared a new post',
     '/post/{post_id}', 7, true, 'new_posts',
     '4 hours', 5, '1 day'),
    
    ('post_flagged', 'Post Flagged', 'system',
     'Your post was flagged',
     'Your post was flagged for review',
     '/post/{post_id}', 3, false, NULL,
     NULL, 1, '30 days'),
    
    ('post_approved', 'Post Approved', 'system',
     'Your post was approved',
     'Your post has been reviewed and approved',
     '/post/{post_id}', 5, false, NULL,
     NULL, 1, '7 days'),
    
    ('post_removed', 'Post Removed', 'system',
     'Your post was removed',
     'Your post was removed for violating community guidelines',
     '/settings/content', 2, false, NULL,
     NULL, 1, NULL),
    
    -- =========================================================================
    -- PRODUCT NOTIFICATIONS
    -- =========================================================================
    ('product_tagged_in_post', 'Product Tagged in Post', 'activity',
     '{actor_name} tagged your product',
     '{actor_name} tagged {product_name} in a post',
     '/post/{post_id}', 4, true, 'product_tagged:{product_id}',
     '1 hour', 20, '3 days'),
    
    ('new_product_from_following', 'New Product', 'activity',
     'New product from {actor_name}',
     '{actor_name} just added {product_name}',
     '/product/{product_id}', 6, true, 'new_products',
     '4 hours', 5, '3 days'),
    
    ('product_dropping_7days', 'Product Dropping Soon', 'promotions',
     '{product_name} drops in 7 days! 📅',
     'Mark your calendar - {product_name} releases in 7 days',
     '/product/{product_id}', 6, false, NULL,
     NULL, 1, '8 days'),
    
    ('product_dropping_1day', 'Product Dropping Tomorrow', 'promotions',
     '{product_name} drops tomorrow! ⏰',
     'Don''t forget - {product_name} releases tomorrow',
     '/product/{product_id}', 4, false, NULL,
     NULL, 1, '2 days'),
    
    ('product_dropped', 'Product Just Dropped', 'promotions',
     '{product_name} just dropped! 🎉',
     '{product_name} is now available',
     '/product/{product_id}', 3, false, NULL,
     NULL, 1, '3 days'),
    
    ('product_stash_milestone', 'Product Stash Milestone', 'activity',
     'Your product is trending! 🔥',
     '{product_name} now has {count} stashes',
     '/product/{product_id}', 6, false, NULL,
     '24 hours', 1, '7 days'),
    
    ('brand_stash_milestone', 'Brand Stash Milestone', 'activity',
     'Your brand is trending! 🔥',
     'Your products now have {count} total stashes',
     '/profile/{profile_id}', 5, false, NULL,
     '24 hours', 1, '7 days'),
    
    ('product_featured', 'Product Featured', 'promotions',
     'Your product was featured! ⭐',
     '{product_name} was featured on the explore page',
     '/product/{product_id}', 3, false, NULL,
     NULL, 1, '7 days'),
    
    -- =========================================================================
    -- GIVEAWAY NOTIFICATIONS  
    -- =========================================================================
    ('giveaway_entered', 'Giveaway Entry Confirmed', 'activity',
     'You''re entered! 🎟️',
     'You''ve been entered into the {giveaway_name} giveaway',
     '/giveaway/{giveaway_id}', 5, false, NULL,
     NULL, 1, '30 days'),
    
    ('giveaway_drawing_3days', 'Giveaway Drawing Soon', 'promotions',
     'Drawing in 3 days! 🎰',
     'The {giveaway_name} giveaway drawing is in 3 days',
     '/giveaway/{giveaway_id}', 6, false, NULL,
     NULL, 1, '4 days'),
    
    ('giveaway_drawing_1day', 'Giveaway Drawing Tomorrow', 'promotions',
     'Drawing tomorrow! 🎰',
     'The {giveaway_name} giveaway drawing is tomorrow',
     '/giveaway/{giveaway_id}', 4, false, NULL,
     NULL, 1, '2 days'),
    
    ('giveaway_drawing_1hour', 'Giveaway Drawing Soon', 'promotions',
     'Drawing in 1 hour! 🎰',
     'The {giveaway_name} giveaway drawing is in 1 hour',
     '/giveaway/{giveaway_id}', 2, false, NULL,
     NULL, 1, '2 hours'),
    
    ('giveaway_won', 'Giveaway Winner!', 'activity',
     'Congratulations! 🎉🎊',
     'You won the {giveaway_name} giveaway!',
     '/giveaway/{giveaway_id}', 1, false, NULL,
     NULL, 1, NULL), -- Never expires
    
    ('giveaway_finished', 'Giveaway Drawing Complete', 'activity',
     'Drawing complete',
     'The {giveaway_name} giveaway drawing has finished. Check results!',
     '/giveaway/{giveaway_id}', 6, false, NULL,
     NULL, 1, '7 days'),
    
    ('new_giveaway_from_following', 'New Giveaway', 'promotions',
     'New giveaway from {actor_name}! 🎁',
     '{actor_name} just launched a new giveaway',
     '/giveaway/{giveaway_id}', 5, true, 'new_giveaways',
     '4 hours', 5, '7 days'),
    
    ('giveaway_shipping_update', 'Giveaway Shipping Update', 'activity',
     'Prize shipping update 📦',
     'Your prize from {giveaway_name} has shipped!',
     '/giveaway/{giveaway_id}', 4, false, NULL,
     NULL, 1, '30 days'),
    
    ('giveaway_new_message', 'Giveaway Message', 'activity',
     'Message about your prize',
     'You have a new message about the {giveaway_name} giveaway',
     '/giveaway/{giveaway_id}', 4, false, NULL,
     NULL, 1, '30 days'),
    
    -- =========================================================================
    -- DEAL NOTIFICATIONS
    -- =========================================================================
    ('new_deal_from_following', 'New Deal', 'promotions',
     'New deal from {actor_name}! 💰',
     '{actor_name} just posted a new deal',
     '/deal/{deal_id}', 5, true, 'new_deals',
     '4 hours', 5, '7 days'),
    
    ('deal_claimed', 'Deal Claimed', 'activity',
     'Deal claimed! ✅',
     'You claimed the deal on {product_name}',
     '/deal/{deal_id}', 6, false, NULL,
     NULL, 1, '7 days'),
    
    ('deal_reminder', 'Deal Reminder', 'promotions',
     'Deal reminder 💰',
     'Don''t forget about the deal on {product_name}',
     '/deal/{deal_id}', 6, false, NULL,
     NULL, 1, '3 days'),
    
    ('deal_expiring_24h', 'Deal Expiring Soon', 'promotions',
     'Deal expires soon! ⏰',
     'The deal on {product_name} expires in 24 hours',
     '/deal/{deal_id}', 4, false, NULL,
     NULL, 1, '2 days'),
    
    ('deal_expiring_1h', 'Deal Expiring Very Soon', 'promotions',
     'Deal expires in 1 hour! ⏰',
     'Last chance! The deal on {product_name} expires in 1 hour',
     '/deal/{deal_id}', 2, false, NULL,
     NULL, 1, '2 hours'),
    
    ('deal_expired', 'Deal Expired', 'activity',
     'Deal has ended',
     'The deal on {product_name} has expired',
     '/deal/{deal_id}', 7, false, NULL,
     NULL, 1, '1 day'),
    
    -- =========================================================================
    -- LOCATION NOTIFICATIONS
    -- =========================================================================
    ('new_location_from_following', 'New Location', 'activity',
     '{actor_name} opened a new location',
     '{actor_name} just opened {location_name}',
     '/location/{location_id}', 6, true, 'new_locations',
     '4 hours', 3, '7 days'),
    
    ('location_favorited', 'Location Favorited', 'social',
     '{actor_name} favorited your location',
     '{actor_name} added {location_name} to their favorites',
     '/location/{location_id}', 6, true, 'location_favorited:{location_id}',
     '1 hour', 20, '3 days'),
    
    ('location_near_you', 'Location Near You', 'promotions',
     'New location near you! 📍',
     '{location_name} just opened near you',
     '/location/{location_id}', 6, false, NULL,
     '24 hours', 1, '7 days'),
    
    -- =========================================================================
    -- EMPLOYEE/BUDTENDER NOTIFICATIONS
    -- =========================================================================
    ('employee_request', 'Employee Request', 'activity',
     'New employee request',
     '{actor_name} wants to join {location_name} as a {role}',
     '/location/{location_id}/employees', 4, true, 'employee_requests:{location_id}',
     '4 hours', 10, '7 days'),
    
    ('employee_approved', 'Employee Approved', 'activity',
     'You''ve been approved! 🎉',
     'You''ve been approved as a {role} at {location_name}',
     '/location/{location_id}', 3, false, NULL,
     NULL, 1, '30 days'),
    
    ('employee_rejected', 'Employee Request Rejected', 'activity',
     'Employee request update',
     'Your request to join {location_name} was not approved',
     '/locations', 5, false, NULL,
     NULL, 1, '7 days'),
    
    ('budtender_notification', 'Budtender Update', 'system',
     'Budtender update',
     '{message}',
     '/budtender', 4, false, NULL,
     '1 hour', 5, '7 days'),
    
    -- =========================================================================
    -- PROFILE ADMIN NOTIFICATIONS
    -- =========================================================================
    ('admin_added', 'Added as Admin', 'activity',
     'You''re now an admin! 🔑',
     'You''ve been added as an {role} for {brand_name}',
     '/profile/{profile_id}/manage', 3, false, NULL,
     NULL, 1, '30 days'),
    
    ('admin_removed', 'Admin Access Removed', 'activity',
     'Admin access removed',
     'Your admin access to {brand_name} has been removed',
     '/profile', 4, false, NULL,
     NULL, 1, '7 days'),
    
    -- =========================================================================
    -- ACCOUNT/PROFILE NOTIFICATIONS
    -- =========================================================================
    ('upgraded_to_creator', 'Creator Status', 'system',
     'Welcome, Creator! 🌟',
     'You''ve been upgraded to Creator status',
     '/settings/creator', 2, false, NULL,
     NULL, 1, NULL),
    
    ('profile_verified', 'Profile Verified', 'system',
     'You''re verified! ✓',
     'Your profile has been verified',
     '/profile', 2, false, NULL,
     NULL, 1, NULL),
    
    ('profile_featured', 'Profile Featured', 'promotions',
     'You''ve been featured! ⭐',
     'Your profile was featured on the explore page',
     '/profile', 3, false, NULL,
     NULL, 1, '7 days'),
    
    ('account_warning', 'Account Warning', 'system',
     'Account warning ⚠️',
     'Your account has received a warning. Please review our guidelines.',
     '/settings/account', 2, false, NULL,
     NULL, 1, NULL),
    
    ('account_suspended', 'Account Suspended', 'system',
     'Account suspended',
     'Your account has been suspended',
     '/settings/account', 1, false, NULL,
     NULL, 1, NULL),
    
    ('account_reinstated', 'Account Reinstated', 'system',
     'Account reinstated',
     'Your account has been reinstated',
     '/settings/account', 2, false, NULL,
     NULL, 1, NULL),
    
    -- =========================================================================
    -- SYSTEM NOTIFICATIONS
    -- =========================================================================
    ('general_message', 'Message', 'system',
     '{title}',
     '{message}',
     '{action_url}', 5, false, NULL,
     NULL, 1, '30 days'),
    
    ('security_alert', 'Security Alert', 'system',
     'Security Alert ⚠️',
     'New login detected from {device_name}',
     '/settings/security', 1, false, NULL,
     NULL, 1, NULL),
    
    ('password_changed', 'Password Changed', 'system',
     'Password changed',
     'Your password was successfully changed',
     '/settings/security', 3, false, NULL,
     NULL, 1, '30 days'),
    
    ('email_changed', 'Email Changed', 'system',
     'Email updated',
     'Your email was changed to {new_email}',
     '/settings/account', 3, false, NULL,
     NULL, 1, '30 days'),
    
    ('delete_request_received', 'Delete Request Received', 'system',
     'Account deletion scheduled',
     'Your account is scheduled for deletion in 30 days',
     '/settings/account', 2, false, NULL,
     NULL, 1, NULL),
    
    ('delete_request_cancelled', 'Delete Request Cancelled', 'system',
     'Account deletion cancelled',
     'Your account deletion request has been cancelled',
     '/settings/account', 3, false, NULL,
     NULL, 1, '7 days'),
    
    -- =========================================================================
    -- MILESTONE/ACHIEVEMENT NOTIFICATIONS
    -- =========================================================================
    ('follower_milestone', 'Follower Milestone', 'social',
     'Milestone reached! 🎉',
     'You now have {count} followers!',
     '/profile', 4, false, NULL,
     NULL, 1, '30 days'),
    
    ('post_milestone', 'Post Milestone', 'activity',
     'Post milestone! 📸',
     'Your post reached {count} likes!',
     '/post/{post_id}', 5, false, NULL,
     '24 hours', 1, '7 days'),
    
    ('stash_milestone', 'Stash Milestone', 'activity',
     'Stash growing! 🌱',
     'You''ve stashed {count} products!',
     '/profile/stash', 6, false, NULL,
     NULL, 1, '30 days'),
    
    -- =========================================================================
    -- WEEKLY DIGEST / RECAP NOTIFICATIONS
    -- =========================================================================
    ('weekly_digest', 'Weekly Digest', 'activity',
     'Your weekly recap 📊',
     'See what happened this week: {summary}',
     '/activity', 7, false, NULL,
     NULL, 1, '7 days'),
    
    ('missed_activity', 'Missed Activity', 'activity',
     'While you were away...',
     'You have {count} new notifications',
     '/notifications', 7, false, NULL,
     NULL, 1, '3 days')

ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    category = EXCLUDED.category,
    title_template = EXCLUDED.title_template,
    body_template = EXCLUDED.body_template,
    action_url_template = EXCLUDED.action_url_template,
    priority = EXCLUDED.priority,
    is_groupable = EXCLUDED.is_groupable,
    group_key = EXCLUDED.group_key,
    aggregation_window = EXCLUDED.aggregation_window,
    max_per_window = EXCLUDED.max_per_window,
    auto_expire_after = EXCLUDED.auto_expire_after;

-- ============================================================================
-- ENHANCED SEND NOTIFICATION FUNCTION (with aggregation)
-- Uses integer IDs internally
-- ============================================================================

-- Drop old function if exists with UUID signature
DROP FUNCTION IF EXISTS public.send_notification(uuid, text, uuid, text, uuid, jsonb);

CREATE OR REPLACE FUNCTION public.send_notification(
    p_recipient_id integer,
    p_type_code text,
    p_actor_id integer DEFAULT NULL,
    p_related_type text DEFAULT NULL,
    p_related_id integer DEFAULT NULL,
    p_extra_data jsonb DEFAULT '{}'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_notification_id integer;
    v_aggregate_id integer;
    v_type public.notification_types%ROWTYPE;
    v_prefs public.notification_preferences%ROWTYPE;
    v_actor public.profiles%ROWTYPE;
    v_title text;
    v_body text;
    v_action_url text;
    v_channels public.notification_channel[];
    v_aggregate_key text;
    v_existing_aggregate public.notification_aggregates%ROWTYPE;
    v_should_create_notification boolean := true;
    v_window_start timestamptz;
    v_key text;
BEGIN
    -- Get notification type
    SELECT * INTO v_type FROM public.notification_types WHERE code = p_type_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown notification type: %', p_type_code;
    END IF;
    
    -- Get user preferences
    SELECT * INTO v_prefs FROM public.notification_preferences WHERE profile_id = p_recipient_id;
    
    -- Check if this type is disabled
    IF v_prefs.disabled_types IS NOT NULL AND v_prefs.disabled_types @> ARRAY[p_type_code] THEN
        RETURN NULL;
    END IF;
    
    -- Check if user is muted
    IF v_prefs.is_muted_until IS NOT NULL AND v_prefs.is_muted_until > now() THEN
        RETURN NULL;
    END IF;
    
    -- Get actor info for template rendering
    IF p_actor_id IS NOT NULL THEN
        SELECT * INTO v_actor FROM public.profiles WHERE id = p_actor_id;
    END IF;
    
    -- Handle aggregation if this notification type is groupable
    IF v_type.is_groupable AND v_type.group_key IS NOT NULL THEN
        -- Build the aggregate key
        v_aggregate_key := v_type.group_key;
        IF p_related_id IS NOT NULL THEN
            v_aggregate_key := replace(v_aggregate_key, '{post_id}', coalesce(p_related_id::text, ''));
            v_aggregate_key := replace(v_aggregate_key, '{product_id}', coalesce(p_related_id::text, ''));
            v_aggregate_key := replace(v_aggregate_key, '{list_id}', coalesce(p_related_id::text, ''));
            v_aggregate_key := replace(v_aggregate_key, '{giveaway_id}', coalesce(p_related_id::text, ''));
        END IF;
        
        -- Calculate window start
        v_window_start := now() - coalesce(v_type.aggregation_window, '1 hour'::interval);
        
        -- Check for existing aggregate in the window
        SELECT * INTO v_existing_aggregate
        FROM public.notification_aggregates
        WHERE profile_id = p_recipient_id
          AND aggregate_key = v_aggregate_key
          AND window_start > v_window_start;
        
        IF v_existing_aggregate.id IS NOT NULL THEN
            -- Update existing aggregate
            UPDATE public.notification_aggregates
            SET 
                count = count + 1,
                actor_ids = CASE 
                    WHEN p_actor_id IS NOT NULL AND NOT (actor_ids @> ARRAY[p_actor_id])
                    THEN (actor_ids || p_actor_id)[1:max_display_actors + 2] -- Keep a few extra
                    ELSE actor_ids
                END,
                last_updated_at = now(),
                is_seen = false
            WHERE id = v_existing_aggregate.id;
            
            v_aggregate_id := v_existing_aggregate.id;
            
            -- Check if we should still create a notification based on max_per_window
            IF v_existing_aggregate.count >= coalesce(v_type.max_per_window, 1) THEN
                v_should_create_notification := false;
            END IF;
        ELSE
            -- Create new aggregate
            INSERT INTO public.notification_aggregates (
                profile_id, aggregate_key, type_code, related_type, related_id,
                actor_ids, window_start
            ) VALUES (
                p_recipient_id, v_aggregate_key, p_type_code, p_related_type, p_related_id,
                CASE WHEN p_actor_id IS NOT NULL THEN ARRAY[p_actor_id] ELSE '{}' END,
                now()
            ) RETURNING id INTO v_aggregate_id;
        END IF;
    END IF;
    
    -- Create the notification if we should
    IF v_should_create_notification THEN
        -- Render templates
        v_title := v_type.title_template;
        v_body := v_type.body_template;
        v_action_url := v_type.action_url_template;
        
        -- Replace actor placeholders (use public_id for URLs)
        IF v_actor.id IS NOT NULL THEN
            v_title := replace(v_title, '{actor_name}', coalesce(v_actor.display_name, v_actor.username, 'Someone'));
            v_body := replace(v_body, '{actor_name}', coalesce(v_actor.display_name, v_actor.username, 'Someone'));
            v_action_url := replace(v_action_url, '{actor_id}', v_actor.public_id::text);
        END IF;
        
        -- Replace related entity placeholders (use public_id for URLs)
        IF p_related_id IS NOT NULL AND p_related_type IS NOT NULL THEN
            -- Get public_id based on related_type
            v_action_url := replace(v_action_url, '{' || p_related_type || '_id}', 
                CASE p_related_type
                    WHEN 'post' THEN (SELECT public_id::text FROM posts WHERE id = p_related_id)
                    WHEN 'product' THEN (SELECT public_id::text FROM products WHERE id = p_related_id)
                    WHEN 'list' THEN (SELECT public_id::text FROM lists WHERE id = p_related_id)
                    WHEN 'giveaway' THEN (SELECT public_id::text FROM giveaways WHERE id = p_related_id)
                    WHEN 'deal' THEN (SELECT public_id::text FROM deals WHERE id = p_related_id)
                    WHEN 'location' THEN (SELECT public_id::text FROM locations WHERE id = p_related_id)
                    WHEN 'profile' THEN (SELECT public_id::text FROM profiles WHERE id = p_related_id)
                    ELSE p_related_id::text
                END
            );
        END IF;
        
        -- Replace any extra data placeholders
        IF p_extra_data IS NOT NULL AND p_extra_data != '{}' THEN
            FOR v_key IN SELECT jsonb_object_keys(p_extra_data) LOOP
                v_title := replace(v_title, '{' || v_key || '}', p_extra_data->>v_key);
                v_body := replace(v_body, '{' || v_key || '}', p_extra_data->>v_key);
                v_action_url := replace(v_action_url, '{' || v_key || '}', p_extra_data->>v_key);
            END LOOP;
        END IF;
        
        -- Determine channels based on preferences
        v_channels := CASE v_type.category
            WHEN 'social' THEN coalesce(v_prefs.social_channels, v_type.default_channels)
            WHEN 'activity' THEN coalesce(v_prefs.activity_channels, v_type.default_channels)
            WHEN 'promotions' THEN coalesce(v_prefs.promotions_channels, v_type.default_channels)
            WHEN 'system' THEN coalesce(v_prefs.system_channels, v_type.default_channels)
            ELSE v_type.default_channels
        END;
        
        -- Insert notification
        INSERT INTO public.notifications (
            profile_id, type_id, title, body, action_url, actor_id,
            related_type, related_id, data, group_key, aggregate_id, priority,
            post_id, product_id, giveaway_id, deal_id, list_id,
            expires_at
        ) VALUES (
            p_recipient_id, v_type.id, v_title, v_body, v_action_url, p_actor_id,
            p_related_type, p_related_id, p_extra_data, 
            v_aggregate_key, v_aggregate_id, v_type.priority,
            CASE WHEN p_related_type = 'post' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'product' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'giveaway' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'deal' THEN p_related_id ELSE NULL END,
            CASE WHEN p_related_type = 'list' THEN p_related_id ELSE NULL END,
            CASE WHEN v_type.auto_expire_after IS NOT NULL 
                 THEN now() + v_type.auto_expire_after 
                 ELSE NULL END
        ) RETURNING id INTO v_notification_id;
        
        -- Update aggregate with representative notification
        IF v_aggregate_id IS NOT NULL THEN
            UPDATE public.notification_aggregates
            SET notification_id = coalesce(notification_id, v_notification_id)
            WHERE id = v_aggregate_id;
        END IF;
        
        -- Queue push notification if channel is enabled
        IF 'push' = ANY(v_channels) THEN
            INSERT INTO public.push_queue (notification_id, push_token_id, payload, priority)
            SELECT 
                v_notification_id,
                pt.id,
                jsonb_build_object(
                    'title', v_title,
                    'body', v_body,
                    'sound', coalesce(v_type.sound_name, 'default'),
                    'badge', v_type.badge_increment,
                    'data', jsonb_build_object(
                        'notification_id', v_notification_id,
                        'action_url', v_action_url,
                        'type', p_type_code,
                        'related_type', p_related_type,
                        'related_id', p_related_id
                    ) || coalesce(p_extra_data, '{}')
                ),
                v_type.priority
            FROM public.push_tokens pt
            WHERE pt.profile_id = p_recipient_id
              AND pt.is_active = true;
        END IF;
    ELSE
        -- Just update the aggregate notification text if aggregating
        IF v_aggregate_id IS NOT NULL AND v_existing_aggregate.notification_id IS NOT NULL THEN
            UPDATE public.notifications
            SET 
                collapsed_count = v_existing_aggregate.count,
                is_aggregated = true,
                title = CASE 
                    WHEN v_existing_aggregate.count = 2 
                    THEN (SELECT coalesce(display_name, username, 'Someone') FROM public.profiles WHERE id = v_existing_aggregate.actor_ids[1])
                         || ' and 1 other'
                    ELSE (SELECT coalesce(display_name, username, 'Someone') FROM public.profiles WHERE id = v_existing_aggregate.actor_ids[1])
                         || ' and ' || (v_existing_aggregate.count - 1)::text || ' others'
                END || ' ' || split_part(title, ' ', 2), -- Append rest of original title
                updated_at = now()
            WHERE id = v_existing_aggregate.notification_id;
            
            v_notification_id := v_existing_aggregate.notification_id;
        END IF;
    END IF;
    
    RETURN v_notification_id;
END;
$$;

-- ============================================================================
-- SCHEDULE NOTIFICATION FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.schedule_notification(
    p_recipient_id integer,
    p_type_code text,
    p_scheduled_for timestamptz,
    p_actor_id integer DEFAULT NULL,
    p_related_type text DEFAULT NULL,
    p_related_id integer DEFAULT NULL,
    p_extra_data jsonb DEFAULT '{}',
    p_idempotency_key text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_scheduled_id integer;
BEGIN
    -- Check for existing scheduled notification with same idempotency key
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_scheduled_id
        FROM public.scheduled_notifications
        WHERE idempotency_key = p_idempotency_key;
        
        IF FOUND THEN
            RETURN v_scheduled_id;
        END IF;
    END IF;
    
    INSERT INTO public.scheduled_notifications (
        profile_id, type_code, scheduled_for, actor_id,
        related_type, related_id, extra_data, idempotency_key
    ) VALUES (
        p_recipient_id, p_type_code, p_scheduled_for, p_actor_id,
        p_related_type, p_related_id, p_extra_data, p_idempotency_key
    ) RETURNING id INTO v_scheduled_id;
    
    RETURN v_scheduled_id;
END;
$$;

-- ============================================================================
-- PROCESS SCHEDULED NOTIFICATIONS (call via cron job)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_scheduled_notifications()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_scheduled public.scheduled_notifications%ROWTYPE;
    v_processed integer := 0;
    v_notification_id integer;
BEGIN
    FOR v_scheduled IN 
        SELECT * FROM public.scheduled_notifications
        WHERE status = 'pending'
          AND scheduled_for <= now()
        ORDER BY scheduled_for
        LIMIT 100 -- Process in batches
        FOR UPDATE SKIP LOCKED
    LOOP
        BEGIN
            -- Send the notification
            v_notification_id := public.send_notification(
                v_scheduled.profile_id,
                v_scheduled.type_code,
                v_scheduled.actor_id,
                v_scheduled.related_type,
                v_scheduled.related_id,
                v_scheduled.extra_data
            );
            
            -- Mark as sent
            UPDATE public.scheduled_notifications
            SET status = 'sent', sent_at = now()
            WHERE id = v_scheduled.id;
            
            v_processed := v_processed + 1;
            
        EXCEPTION WHEN OTHERS THEN
            -- Mark as failed
            UPDATE public.scheduled_notifications
            SET status = 'failed', error_message = SQLERRM
            WHERE id = v_scheduled.id;
        END;
    END LOOP;
    
    RETURN v_processed;
END;
$$;

-- ============================================================================
-- BATCH PUSH NOTIFICATIONS FUNCTION (call via worker)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_push_batch(
    p_max_messages integer DEFAULT 2000, -- OneSignal limit is 2000 per request
    p_provider text DEFAULT 'onesignal'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_batch_id integer;
    v_message_count integer;
BEGIN
    -- Create batch
    INSERT INTO public.push_batches (provider)
    VALUES (p_provider)
    RETURNING id INTO v_batch_id;
    
    -- Assign pending messages to this batch
    WITH assigned AS (
        UPDATE public.push_queue
        SET batch_id = v_batch_id
        WHERE id IN (
            SELECT id FROM public.push_queue
            WHERE status = 'pending'
              AND batch_id IS NULL
              AND (send_at IS NULL OR send_at <= now())
              AND (retry_after IS NULL OR retry_after <= now())
            ORDER BY priority ASC, created_at ASC
            LIMIT p_max_messages
            FOR UPDATE SKIP LOCKED
        )
        RETURNING id
    )
    SELECT count(*) INTO v_message_count FROM assigned;
    
    -- Update batch with count
    UPDATE public.push_batches
    SET message_count = v_message_count, started_at = now()
    WHERE id = v_batch_id;
    
    -- If no messages, clean up
    IF v_message_count = 0 THEN
        DELETE FROM public.push_batches WHERE id = v_batch_id;
        RETURN NULL;
    END IF;
    
    RETURN v_batch_id;
END;
$$;

-- ============================================================================
-- GET AGGREGATED NOTIFICATIONS FOR USER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_notifications(
    p_profile_id integer,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0,
    p_unread_only boolean DEFAULT false
)
RETURNS TABLE (
    id integer,
    public_id uuid,
    type_code text,
    title text,
    body text,
    image_url text,
    action_url text,
    actor_id integer,
    actor_public_id uuid,
    actor_name text,
    actor_avatar text,
    related_type text,
    related_id integer,
    is_read boolean,
    is_aggregated boolean,
    aggregated_count integer,
    aggregated_actors jsonb,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        n.id,
        n.public_id,
        nt.code as type_code,
        n.title,
        n.body,
        n.image_url,
        n.action_url,
        n.actor_id,
        p.public_id as actor_public_id,
        p.display_name as actor_name,
        p.avatar_url as actor_avatar,
        n.related_type,
        n.related_id,
        n.is_read,
        n.is_aggregated,
        COALESCE(n.collapsed_count, 1) as aggregated_count,
        CASE 
            WHEN na.id IS NOT NULL THEN (
                SELECT jsonb_agg(jsonb_build_object(
                    'id', ap.id,
                    'public_id', ap.public_id,
                    'name', ap.display_name,
                    'avatar', ap.avatar_url
                ))
                FROM unnest(na.actor_ids[1:na.max_display_actors]) AS actor_id_elem
                JOIN public.profiles ap ON ap.id = actor_id_elem
            )
            ELSE NULL
        END as aggregated_actors,
        n.created_at
    FROM public.notifications n
    JOIN public.notification_types nt ON nt.id = n.type_id
    LEFT JOIN public.profiles p ON p.id = n.actor_id
    LEFT JOIN public.notification_aggregates na ON na.id = n.aggregate_id
    WHERE n.profile_id = p_profile_id
      AND (NOT p_unread_only OR n.is_read = false)
      AND (n.expires_at IS NULL OR n.expires_at > now())
      AND (na.id IS NULL OR na.notification_id = n.id) -- Only get representative notification for aggregates
    ORDER BY n.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- ============================================================================
-- HELPER: Schedule product drop notifications
-- ============================================================================

CREATE OR REPLACE FUNCTION public.schedule_product_drop_notifications(
    p_product_id integer,
    p_release_date timestamptz,
    p_follower_profile_ids integer[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_product public.products%ROWTYPE;
    v_profile_id integer;
BEGIN
    SELECT * INTO v_product FROM public.products WHERE id = p_product_id;
    
    FOREACH v_profile_id IN ARRAY p_follower_profile_ids
    LOOP
        -- 7 day reminder
        IF p_release_date - interval '7 days' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'product_dropping_7days',
                p_release_date - interval '7 days',
                NULL,
                'product',
                p_product_id,
                jsonb_build_object('product_name', v_product.name),
                'product_7day_' || p_product_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- 1 day reminder
        IF p_release_date - interval '1 day' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'product_dropping_1day',
                p_release_date - interval '1 day',
                NULL,
                'product',
                p_product_id,
                jsonb_build_object('product_name', v_product.name),
                'product_1day_' || p_product_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- Drop notification
        PERFORM public.schedule_notification(
            v_profile_id,
            'product_dropped',
            p_release_date,
            NULL,
            'product',
            p_product_id,
            jsonb_build_object('product_name', v_product.name),
            'product_dropped_' || p_product_id::text || '_' || v_profile_id::text
        );
    END LOOP;
END;
$$;

-- ============================================================================
-- HELPER: Schedule giveaway notifications
-- ============================================================================

CREATE OR REPLACE FUNCTION public.schedule_giveaway_notifications(
    p_giveaway_id integer,
    p_end_time timestamptz,
    p_entrant_profile_ids integer[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_giveaway public.giveaways%ROWTYPE;
    v_profile_id integer;
BEGIN
    SELECT * INTO v_giveaway FROM public.giveaways WHERE id = p_giveaway_id;
    
    FOREACH v_profile_id IN ARRAY p_entrant_profile_ids
    LOOP
        -- 3 day reminder
        IF p_end_time - interval '3 days' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'giveaway_drawing_3days',
                p_end_time - interval '3 days',
                NULL,
                'giveaway',
                p_giveaway_id,
                jsonb_build_object('giveaway_name', v_giveaway.name),
                'giveaway_3day_' || p_giveaway_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- 1 day reminder
        IF p_end_time - interval '1 day' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'giveaway_drawing_1day',
                p_end_time - interval '1 day',
                NULL,
                'giveaway',
                p_giveaway_id,
                jsonb_build_object('giveaway_name', v_giveaway.name),
                'giveaway_1day_' || p_giveaway_id::text || '_' || v_profile_id::text
            );
        END IF;
        
        -- 1 hour reminder
        IF p_end_time - interval '1 hour' > now() THEN
            PERFORM public.schedule_notification(
                v_profile_id,
                'giveaway_drawing_1hour',
                p_end_time - interval '1 hour',
                NULL,
                'giveaway',
                p_giveaway_id,
                jsonb_build_object('giveaway_name', v_giveaway.name),
                'giveaway_1hour_' || p_giveaway_id::text || '_' || v_profile_id::text
            );
        END IF;
    END LOOP;
END;
$$;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.scheduled_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_aggregates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_batches ENABLE ROW LEVEL SECURITY;

-- Scheduled notifications - users can see their own
CREATE POLICY "Users can view their own scheduled notifications" ON public.scheduled_notifications 
    FOR SELECT USING (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id));

CREATE POLICY "Service role full access to scheduled_notifications" ON public.scheduled_notifications 
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Notification aggregates - users can see their own
CREATE POLICY "Users can view their own notification aggregates" ON public.notification_aggregates 
    FOR SELECT USING (auth.uid() = (SELECT auth_id FROM profiles WHERE id = profile_id));

CREATE POLICY "Service role full access to notification_aggregates" ON public.notification_aggregates 
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Push batches - service role only
CREATE POLICY "Service role only for push_batches" ON public.push_batches 
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL ON TABLE public.scheduled_notifications TO authenticated;
GRANT ALL ON TABLE public.scheduled_notifications TO service_role;

GRANT ALL ON TABLE public.notification_aggregates TO authenticated;
GRANT ALL ON TABLE public.notification_aggregates TO service_role;

GRANT ALL ON TABLE public.push_batches TO authenticated;
GRANT ALL ON TABLE public.push_batches TO service_role;

GRANT EXECUTE ON FUNCTION public.send_notification(integer, text, integer, text, integer, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_notification(integer, text, integer, text, integer, jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.schedule_notification TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_notification TO service_role;

GRANT EXECUTE ON FUNCTION public.get_notifications TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notifications TO service_role;

GRANT EXECUTE ON FUNCTION public.process_scheduled_notifications TO service_role;
GRANT EXECUTE ON FUNCTION public.create_push_batch TO service_role;
