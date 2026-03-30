-- Giveaway Messaging RPCs

-- Get giveaways for admin view (ended or has winners)
CREATE OR REPLACE FUNCTION public.get_admin_giveaways(
    p_limit integer DEFAULT 20,
    p_offset integer DEFAULT 0
)
RETURNS SETOF json
LANGUAGE sql
STABLE
AS $$
    SELECT json_build_object(
        'id', g.public_id,
        'name', g.name,
        'end_time', g.end_time,
        'winner_count', g.winner_count,
        'entry_count', g.entry_count,
        'product', (SELECT row_to_json(p) FROM public.products p WHERE p.id = g.product_id),
        'cover', (SELECT row_to_json(c) FROM public.cloud_files c WHERE c.id = g.cover_id)
    )
    FROM public.giveaways g
    WHERE g.end_time < now() OR g.winner_count > 0
    ORDER BY g.end_time DESC
    LIMIT p_limit OFFSET p_offset;
$$;

-- Get winners for a specific giveaway
CREATE OR REPLACE FUNCTION public.get_giveaway_winners(
    p_giveaway_id uuid
)
RETURNS SETOF json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_giveaway_int_id integer;
BEGIN
    SELECT id INTO v_giveaway_int_id FROM public.giveaways WHERE public_id = p_giveaway_id;

    RETURN QUERY
    SELECT json_build_object(
        'id', ge.public_id,
        'won', ge.won,
        'sent', ge.sent,
        'shipping_notes', ge.shipping_notes,
        'profile', (
            SELECT json_build_object(
                'id', p.public_id,
                'username', p.username,
                'display_name', p.display_name,
                'avatar', (SELECT row_to_json(cf) FROM public.cloud_files cf WHERE cf.id = p.avatar_id)
            )
            FROM public.profiles p WHERE p.id = ge.profile_id
        ),
        'address', (
            SELECT row_to_json(a) 
            FROM public.addresses a 
            WHERE a.profile_id = ge.profile_id 
            ORDER BY a.created_at DESC LIMIT 1
        )
    )
    FROM public.giveaway_entries ge
    WHERE ge.giveaway_id = v_giveaway_int_id AND ge.won = true;
END;
$$;

-- Get won giveaways for a user
CREATE OR REPLACE FUNCTION public.get_user_won_giveaways(
    p_profile_id uuid
)
RETURNS SETOF json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_profile_int_id integer;
BEGIN
    SELECT id INTO v_profile_int_id FROM public.profiles WHERE public_id = p_profile_id;

    RETURN QUERY
    SELECT json_build_object(
        'entry_id', ge.public_id,
        'won', ge.won,
        'sent', ge.sent,
        'giveaway', (
            SELECT json_build_object(
                'id', g.public_id,
                'name', g.name,
                'description', g.description,
                'cover', (SELECT row_to_json(c) FROM public.cloud_files c WHERE c.id = g.cover_id)
            )
            FROM public.giveaways g WHERE g.id = ge.giveaway_id
        )
    )
    FROM public.giveaway_entries ge
    WHERE ge.profile_id = v_profile_int_id AND ge.won = true;
END;
$$;

-- Get messages for a specific entry
CREATE OR REPLACE FUNCTION public.get_giveaway_messages(
    p_entry_id uuid
)
RETURNS SETOF json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_entry_int_id integer;
BEGIN
    SELECT id INTO v_entry_int_id FROM public.giveaway_entries WHERE public_id = p_entry_id;

    RETURN QUERY
    SELECT json_build_object(
        'id', gem.public_id,
        'message', gem.message,
        'created_at', gem.created_at,
        'sender', (
            SELECT json_build_object(
                'id', p.public_id,
                'username', p.username,
                'avatar', (SELECT row_to_json(cf) FROM public.cloud_files cf WHERE cf.id = p.avatar_id)
            )
            FROM public.profiles p WHERE p.id = gem.profile_id
        )
    )
    FROM public.giveaway_entries_messages gem
    WHERE gem.giveaway_entry_id = v_entry_int_id
    ORDER BY gem.created_at ASC;
END;
$$;

-- Send a message
CREATE OR REPLACE FUNCTION public.send_giveaway_message(
    p_entry_id uuid,
    p_message text,
    p_sender_id uuid
)
RETURNS json
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_entry_int_id integer;
    v_sender_int_id integer;
    v_message_id integer;
    v_result json;
BEGIN
    SELECT id INTO v_entry_int_id FROM public.giveaway_entries WHERE public_id = p_entry_id;
    SELECT id INTO v_sender_int_id FROM public.profiles WHERE public_id = p_sender_id;

    INSERT INTO public.giveaway_entries_messages (giveaway_entry_id, profile_id, message)
    VALUES (v_entry_int_id, v_sender_int_id, p_message)
    RETURNING id INTO v_message_id;

    SELECT json_build_object(
        'id', gem.public_id,
        'message', gem.message,
        'created_at', gem.created_at
    ) INTO v_result
    FROM public.giveaway_entries_messages gem
    WHERE gem.id = v_message_id;

    RETURN v_result;
END;
$$;
