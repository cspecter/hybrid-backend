-- Point products at our own copies of their images.
--
-- 418,251 images have been fetched, resized and stored, and the app has been serving
-- none of them: products.gallery_urls still holds the URL the feed supplied, so every
-- view goes to one of 29 third-party CDNs. 4.6 GB of storage doing nothing.
--
-- gallery_urls becomes [our copy, the original]. The app reads element 0, so the
-- storage copy is what renders; element 1 stays as a fallback for the ~1,800 that
-- failed to fetch and for the case where a stored object is ever missing. Nothing is
-- discarded — product_images keeps source_url regardless.
--
-- A function, not a migration. The last time something that has to run after every
-- import was written as a migration it ran once and silently stopped applying to
-- everything promoted afterwards.
create or replace function public.apply_stored_product_images()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_base constant text := 'https://ujmisqstpmowanvivtcr.supabase.co/storage/v1/object/public/product-images/';
  v_n integer;
begin
  update public.products p
     set gallery_urls = array[c_base || pi.storage_path, pi.source_url],
         updated_at = now()
    from public.product_images pi
   where p.source = 'litalerts'
     and pi.status = 'stored'
     and pi.storage_path is not null
     -- Element 0 is still the source URL, i.e. not yet switched over.
     and p.gallery_urls[1] = pi.source_url;
  get diagnostics v_n = row_count;

  return jsonb_build_object(
    'products_switched_to_storage', v_n,
    'feed_products_on_storage', (select count(*) from public.products
                                  where source='litalerts' and gallery_urls[1] like c_base || '%'),
    'feed_products_still_hotlinking', (select count(*) from public.products
                                        where source='litalerts'
                                          and array_length(gallery_urls,1) > 0
                                          and gallery_urls[1] not like c_base || '%'),
    'feed_products_with_no_image', (select count(*) from public.products
                                     where source='litalerts'
                                       and coalesce(array_length(gallery_urls,1),0) = 0));
end;
$$;

revoke all on function public.apply_stored_product_images() from public, anon, authenticated;
