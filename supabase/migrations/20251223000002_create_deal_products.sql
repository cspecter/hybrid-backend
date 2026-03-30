-- Create deal_products join table
DROP TABLE IF EXISTS public.deal_products CASCADE;

CREATE TABLE IF NOT EXISTS public.deal_products (
    deal_id integer REFERENCES public.deals(id) ON DELETE CASCADE,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (deal_id, product_id)
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_deal_products_deal_id ON public.deal_products(deal_id);
CREATE INDEX IF NOT EXISTS idx_deal_products_product_id ON public.deal_products(product_id);

-- Enable RLS
ALTER TABLE public.deal_products ENABLE ROW LEVEL SECURITY;

-- Add policies
CREATE POLICY "Public deals are viewable by everyone." ON public.deal_products FOR SELECT USING (true);

CREATE POLICY "Super admins can insert deal_products." ON public.deal_products FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.super_admins WHERE auth_id = auth.uid()
  )
);

CREATE POLICY "Super admins can update deal_products." ON public.deal_products FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.super_admins WHERE auth_id = auth.uid()
  )
);

CREATE POLICY "Super admins can delete deal_products." ON public.deal_products FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM public.super_admins WHERE auth_id = auth.uid()
  )
);
