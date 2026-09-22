create or replace function public.boostable_posts(
  p_query text default null,
  p_post_id integer default null,
  p_limit integer default 12)
returns table (
  post_id integer, message text, author_name text, author_handle text,
  image_url text, created_at timestamptz, like_count integer, already_boosted boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- Backs the post picker on the sponsored campaign form, which until now asked for a
-- numeric post id — findable only by someone willing to go looking in the database,
-- which is nobody, including the person who wrote it.
--
-- One function rather than a search and a fetch-by-id, because the form needs both
-- and they differ only in the WHERE: searching while choosing, and resolving the id
-- back to a card when an existing campaign is reopened for editing.
--
-- Moderation only. These are public posts, so this leaks nothing a feed would not,
-- but it is a full-text sweep over every post on the platform and that is not a
-- capability to hand out just because the rows happen to be readable.
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_as_id integer := case when v_q ~ '^[0-9]+$' then v_q::integer else null end;
begin
  if not public.is_super_admin() then
    return;
  end if;

  return query
    select p.id,
           left(coalesce(p.message, ''), 160)::text,
           coalesce(a.display_name, a.username, 'Unknown')::text,
           case when a.username is null then '' else '@' || a.username end::text,
           coalesce(cf.secure_url, cf.url, cf2.secure_url, cf2.url)::text,
           p.created_at,
           coalesce(p.like_count, 0),
           exists (
             select 1 from public.sponsored_campaigns c
              where c.post_id = p.id
                and c.status = 'active'
                and (c.starts_at is null or c.starts_at <= now())
                and (c.ends_at is null or c.ends_at > now()))
      from public.posts p
      left join public.profiles a on a.id = p.profile_id
      left join public.cloud_files cf on cf.id = p.file_id
      -- Falls back to the first attached file for posts that carry their media in
      -- posts_files rather than posts.file_id.
      left join lateral (
        select c2.secure_url, c2.url
          from public.posts_files pf
          join public.cloud_files c2 on c2.id = pf.file_id
         where pf.post_id = p.id
         order by pf.position nulls last, pf.file_id
         limit 1) cf2 on true
     where (p_post_id is not null and p.id = p_post_id)
        or (p_post_id is null and (
              v_q = ''
              or (v_as_id is not null and p.id = v_as_id)
              or lower(coalesce(p.message, '')) like '%' || v_q || '%'
              or lower(coalesce(a.username, '')) like '%' || v_q || '%'
              or lower(coalesce(a.display_name, '')) like '%' || v_q || '%'))
     order by p.created_at desc
     limit greatest(coalesce(p_limit, 12), 1);
end;
$$;

revoke execute on function public.boostable_posts(text, integer, integer) from public;
grant execute on function public.boostable_posts(text, integer, integer) to authenticated;
