-- The app reads the catalogue signed in or not, so both roles need the identity views.
-- They expose only a product id and the id of the row representing it; the normaliser's
-- own tables stay unreadable.
grant select on public.v_product_canonical, public.v_product_identity to anon, authenticated;
