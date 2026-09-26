-- The bucket the cached renditions live in.
--
-- Public because these are product photographs shown on menus to anyone browsing the
-- app; there is nothing to authorise and signing 420,169 URLs on every page would be
-- cost without benefit. Writes are a different matter and stay with the service role:
-- no policy is granted to anon or authenticated, so only the ingest worker can put
-- anything here.
--
-- 5 MB ceiling, which no stored rendition should come near — a 400px WebP is tens of
-- kilobytes. It is there to stop a bug uploading an untouched 15 MB original, which
-- the feed demonstrably contains.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880,
        array['image/webp','image/jpeg','image/png'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Read for everyone, write for nobody but the service role.
drop policy if exists "product images are publicly readable" on storage.objects;
create policy "product images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'product-images');
