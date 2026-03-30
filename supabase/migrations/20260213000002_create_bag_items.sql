-- Shopping bag items per profile
CREATE TABLE IF NOT EXISTS public.bag_items (
    id integer NOT NULL,
    profile_id integer NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    product_id integer NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT bag_items_pkey PRIMARY KEY (id),
    CONSTRAINT bag_items_unique UNIQUE (profile_id, product_id)
);

ALTER TABLE public.bag_items OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.bag_items_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.bag_items_id_seq OWNER TO postgres;
ALTER SEQUENCE public.bag_items_id_seq OWNED BY public.bag_items.id;
ALTER TABLE ONLY public.bag_items ALTER COLUMN id SET DEFAULT nextval('public.bag_items_id_seq'::regclass);

CREATE INDEX IF NOT EXISTS idx_bag_items_profile ON public.bag_items(profile_id);
CREATE INDEX IF NOT EXISTS idx_bag_items_product ON public.bag_items(product_id);

SELECT public.create_timestamps_trigger('bag_items');

ALTER TABLE public.bag_items ENABLE ROW LEVEL SECURITY;

-- Public can read bag contents only if corresponding policies allow row visibility.
CREATE POLICY "bag_items_select_policy" ON public.bag_items
    FOR SELECT USING (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = bag_items.profile_id)
    );

CREATE POLICY "bag_items_insert_policy" ON public.bag_items
    FOR INSERT WITH CHECK (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = bag_items.profile_id)
    );

CREATE POLICY "bag_items_update_policy" ON public.bag_items
    FOR UPDATE USING (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = bag_items.profile_id)
    ) WITH CHECK (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = bag_items.profile_id)
    );

CREATE POLICY "bag_items_delete_policy" ON public.bag_items
    FOR DELETE USING (
        auth.uid() = (SELECT p.auth_id FROM public.profiles p WHERE p.id = bag_items.profile_id)
    );

GRANT ALL ON TABLE public.bag_items TO authenticated;
GRANT ALL ON TABLE public.bag_items TO service_role;
GRANT ALL ON SEQUENCE public.bag_items_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.bag_items_id_seq TO service_role;
