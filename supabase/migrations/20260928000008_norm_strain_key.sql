-- Two habits of shop typing that split one product into several identities.
--
--   A trailing z for s. "Pop Rockz" and "Pop Rocks", "Rainbow Beltz" and "Rainbow Belts"
--   are one product each. Folding z to s merges them; it also rewrites Gruntz to Grunts
--   and Runtz to Runts, which is fine because it happens to every spelling equally.
--
--   Bare numbers. One shop writes "Spiked Mai Tai #6", the next writes "Spiked Mai Tai".
--   Keeping the 6 splits them. Phenotype numbers are lost, consistently, which is the
--   cheaper of the two errors.
create or replace function public.norm_strain_key(p_resid text) returns text
language sql immutable
set search_path = public
as $$
  select nullif((
    select string_agg(t, ' ' order by t)
    from (
      select distinct regexp_replace(tok, 'z$', 's') as t
      from unnest(regexp_split_to_array(coalesce(p_resid, ''), ' ')) as u(tok)
      where length(tok) > 1
        and tok ~ '[a-z]'          -- drop bare numbers and stray punctuation
    ) z
  ), '');
$$;

comment on function public.norm_strain_key(text) is
  'Turn a strain residue into a matching key: tokens deduplicated, z-for-s folded, bare numbers dropped, sorted so word order stops mattering.';
