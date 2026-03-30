-- Add sort_order column to lists_products table
ALTER TABLE public.lists_products 
ADD COLUMN IF NOT EXISTS sort_order integer DEFAULT 0;

-- Create an index for faster sorting
CREATE INDEX IF NOT EXISTS idx_lists_products_sort_order ON public.lists_products(sort_order);
