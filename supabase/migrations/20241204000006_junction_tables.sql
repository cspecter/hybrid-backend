-- Junction/Relationship Tables
-- This migration creates many-to-many relationship tables
-- Updated: All foreign keys reference integer PKs
-- Updated: Uses profiles instead of users, locations instead of dispensary_locations
-- Removed: cannabis strain junction tables

-- ============================================================================
-- PRODUCT JUNCTION TABLES
-- ============================================================================

-- Product brands junction (links products to brand profiles)
CREATE TABLE IF NOT EXISTS public.product_brands (
    id integer NOT NULL,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    brand_id integer REFERENCES public.profiles(id) ON DELETE CASCADE,
    is_primary boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT product_brands_pkey PRIMARY KEY (id),
    CONSTRAINT product_brands_unique UNIQUE (product_id, brand_id)
);

ALTER TABLE public.product_brands OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.product_brands_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.product_brands_id_seq OWNER TO postgres;
ALTER SEQUENCE public.product_brands_id_seq OWNED BY public.product_brands.id;
ALTER TABLE ONLY public.product_brands ALTER COLUMN id SET DEFAULT nextval('public.product_brands_id_seq'::regclass);

CREATE INDEX idx_product_brands_product ON public.product_brands(product_id);
CREATE INDEX idx_product_brands_brand ON public.product_brands(brand_id);

-- Products cloud files junction
CREATE TABLE IF NOT EXISTS public.products_cloud_files (
    id integer NOT NULL,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    cloud_file_id integer REFERENCES public.cloud_files(id) ON DELETE CASCADE,
    sort integer DEFAULT 0,
    CONSTRAINT products_cloud_files_pkey PRIMARY KEY (id)
);

ALTER TABLE public.products_cloud_files OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.products_cloud_files_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.products_cloud_files_id_seq OWNER TO postgres;
ALTER SEQUENCE public.products_cloud_files_id_seq OWNED BY public.products_cloud_files.id;
ALTER TABLE ONLY public.products_cloud_files ALTER COLUMN id SET DEFAULT nextval('public.products_cloud_files_id_seq'::regclass);

-- Products product features junction
CREATE TABLE IF NOT EXISTS public.products_product_features (
    id integer NOT NULL,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    product_feature_id integer REFERENCES public.product_features(id) ON DELETE CASCADE,
    CONSTRAINT products_product_features_pkey PRIMARY KEY (id)
);

ALTER TABLE public.products_product_features OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.products_product_features_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.products_product_features_id_seq OWNER TO postgres;
ALTER SEQUENCE public.products_product_features_id_seq OWNED BY public.products_product_features.id;
ALTER TABLE ONLY public.products_product_features ALTER COLUMN id SET DEFAULT nextval('public.products_product_features_id_seq'::regclass);

-- Related products junction
CREATE TABLE IF NOT EXISTS public.related_products (
    id integer NOT NULL,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    related_product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT related_products_pkey PRIMARY KEY (id),
    CONSTRAINT related_products_unique UNIQUE (product_id, related_product_id)
);

ALTER TABLE public.related_products OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.related_products_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.related_products_id_seq OWNER TO postgres;
ALTER SEQUENCE public.related_products_id_seq OWNED BY public.related_products.id;
ALTER TABLE ONLY public.related_products ALTER COLUMN id SET DEFAULT nextval('public.related_products_id_seq'::regclass);

SELECT public.create_timestamps_trigger('related_products');

-- Products states junction
CREATE TABLE IF NOT EXISTS public.products_states (
    id integer NOT NULL,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    state_id integer REFERENCES public.states(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT products_states_pkey PRIMARY KEY (id)
);

ALTER TABLE public.products_states OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.products_states_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.products_states_id_seq OWNER TO postgres;
ALTER SEQUENCE public.products_states_id_seq OWNED BY public.products_states.id;
ALTER TABLE ONLY public.products_states ALTER COLUMN id SET DEFAULT nextval('public.products_states_id_seq'::regclass);

SELECT public.create_timestamps_trigger('products_states');

-- ============================================================================
-- LIST JUNCTION TABLES
-- ============================================================================

-- Lists products junction
CREATE TABLE IF NOT EXISTS public.lists_products (
    id integer NOT NULL,
    list_id integer NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
    product_id integer NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT lists_products_pkey PRIMARY KEY (id),
    CONSTRAINT lists_products_unique UNIQUE (list_id, product_id)
);

ALTER TABLE public.lists_products OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.lists_products_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.lists_products_id_seq OWNER TO postgres;
ALTER SEQUENCE public.lists_products_id_seq OWNED BY public.lists_products.id;
ALTER TABLE ONLY public.lists_products ALTER COLUMN id SET DEFAULT nextval('public.lists_products_id_seq'::regclass);

CREATE INDEX idx_lists_products_list ON public.lists_products(list_id);
CREATE INDEX idx_lists_products_product ON public.lists_products(product_id);

-- ============================================================================
-- POST JUNCTION TABLES
-- ============================================================================

-- Posts hashtags junction
CREATE TABLE IF NOT EXISTS public.posts_hashtags (
    id integer NOT NULL,
    post_id integer REFERENCES public.posts(id) ON DELETE CASCADE,
    post_tag_id integer REFERENCES public.post_tags(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT posts_hashtags_pkey PRIMARY KEY (id)
);

ALTER TABLE public.posts_hashtags OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.posts_hashtags_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.posts_hashtags_id_seq OWNER TO postgres;
ALTER SEQUENCE public.posts_hashtags_id_seq OWNED BY public.posts_hashtags.id;
ALTER TABLE ONLY public.posts_hashtags ALTER COLUMN id SET DEFAULT nextval('public.posts_hashtags_id_seq'::regclass);

SELECT public.create_timestamps_trigger('posts_hashtags');

-- Posts lists junction
CREATE TABLE IF NOT EXISTS public.posts_lists (
    id integer NOT NULL,
    post_id integer REFERENCES public.posts(id) ON DELETE CASCADE,
    list_id integer REFERENCES public.lists(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT posts_lists_pkey PRIMARY KEY (id)
);

ALTER TABLE public.posts_lists OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.posts_lists_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.posts_lists_id_seq OWNER TO postgres;
ALTER SEQUENCE public.posts_lists_id_seq OWNED BY public.posts_lists.id;
ALTER TABLE ONLY public.posts_lists ALTER COLUMN id SET DEFAULT nextval('public.posts_lists_id_seq'::regclass);

SELECT public.create_timestamps_trigger('posts_lists');

-- Posts products junction
CREATE TABLE IF NOT EXISTS public.posts_products (
    id integer NOT NULL,
    post_id integer REFERENCES public.posts(id) ON DELETE CASCADE,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT posts_products_pkey PRIMARY KEY (id)
);

ALTER TABLE public.posts_products OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.posts_products_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.posts_products_id_seq OWNER TO postgres;
ALTER SEQUENCE public.posts_products_id_seq OWNED BY public.posts_products.id;
ALTER TABLE ONLY public.posts_products ALTER COLUMN id SET DEFAULT nextval('public.posts_products_id_seq'::regclass);

SELECT public.create_timestamps_trigger('posts_products');

-- Posts profiles junction (for tagging users in posts)
CREATE TABLE IF NOT EXISTS public.posts_profiles (
    id bigint NOT NULL,
    post_id integer REFERENCES public.posts(id) ON DELETE CASCADE,
    profile_id integer REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT posts_profiles_pkey PRIMARY KEY (id)
);

ALTER TABLE public.posts_profiles OWNER TO postgres;

ALTER TABLE public.posts_profiles ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.posts_profiles_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1
);

SELECT public.create_timestamps_trigger('posts_profiles');

-- ============================================================================
-- DEAL JUNCTION TABLES
-- ============================================================================

-- Deals locations junction (was deals_dispensary_locations)
CREATE TABLE IF NOT EXISTS public.deals_locations (
    id integer NOT NULL,
    deal_id integer REFERENCES public.deals(id) ON DELETE CASCADE,
    location_id integer REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT deals_locations_pkey PRIMARY KEY (id),
    CONSTRAINT deals_locations_unique UNIQUE (deal_id, location_id)
);

ALTER TABLE public.deals_locations OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.deals_locations_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.deals_locations_id_seq OWNER TO postgres;
ALTER SEQUENCE public.deals_locations_id_seq OWNED BY public.deals_locations.id;
ALTER TABLE ONLY public.deals_locations ALTER COLUMN id SET DEFAULT nextval('public.deals_locations_id_seq'::regclass);

-- ============================================================================
-- GIVEAWAY JUNCTION TABLES
-- ============================================================================

-- Giveaways regions junction
CREATE TABLE IF NOT EXISTS public.giveaways_regions (
    id integer NOT NULL,
    giveaway_id integer REFERENCES public.giveaways(id) ON DELETE CASCADE,
    region_id integer REFERENCES public.regions(id) ON DELETE CASCADE,
    CONSTRAINT giveaways_regions_pkey PRIMARY KEY (id),
    CONSTRAINT giveaways_regions_unique UNIQUE (giveaway_id, region_id)
);

ALTER TABLE public.giveaways_regions OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.giveaways_regions_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.giveaways_regions_id_seq OWNER TO postgres;
ALTER SEQUENCE public.giveaways_regions_id_seq OWNED BY public.giveaways_regions.id;
ALTER TABLE ONLY public.giveaways_regions ALTER COLUMN id SET DEFAULT nextval('public.giveaways_regions_id_seq'::regclass);

-- ============================================================================
-- LOCATION JUNCTION TABLES
-- ============================================================================

-- Locations cloud files junction (was dispensary_locations_cloud_files)
CREATE TABLE IF NOT EXISTS public.locations_cloud_files (
    id integer NOT NULL,
    location_id integer REFERENCES public.locations(id) ON DELETE CASCADE,
    cloud_file_id integer REFERENCES public.cloud_files(id) ON DELETE CASCADE,
    sort integer DEFAULT 0,
    CONSTRAINT locations_cloud_files_pkey PRIMARY KEY (id)
);

ALTER TABLE public.locations_cloud_files OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.locations_cloud_files_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.locations_cloud_files_id_seq OWNER TO postgres;
ALTER SEQUENCE public.locations_cloud_files_id_seq OWNED BY public.locations_cloud_files.id;
ALTER TABLE ONLY public.locations_cloud_files ALTER COLUMN id SET DEFAULT nextval('public.locations_cloud_files_id_seq'::regclass);

-- ============================================================================
-- REGION JUNCTION TABLES
-- ============================================================================

-- Region postal codes junction
CREATE TABLE IF NOT EXISTS public.region_postal_codes (
    id integer NOT NULL,
    region_id integer REFERENCES public.regions(id) ON DELETE CASCADE,
    postal_code_id integer REFERENCES public.postal_codes(id) ON DELETE CASCADE,
    CONSTRAINT region_postal_codes_pkey PRIMARY KEY (id),
    CONSTRAINT region_postal_codes_unique UNIQUE (region_id, postal_code_id)
);

ALTER TABLE public.region_postal_codes OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.region_postal_codes_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.region_postal_codes_id_seq OWNER TO postgres;
ALTER SEQUENCE public.region_postal_codes_id_seq OWNED BY public.region_postal_codes.id;
ALTER TABLE ONLY public.region_postal_codes ALTER COLUMN id SET DEFAULT nextval('public.region_postal_codes_id_seq'::regclass);

-- ============================================================================
-- EXPLORE JUNCTION TABLES
-- ============================================================================

-- Explore locations junction (was explore_dispensary_locations)
CREATE TABLE IF NOT EXISTS public.explore_locations (
    id integer NOT NULL,
    explore_id integer REFERENCES public.explore(id) ON DELETE CASCADE,
    location_id integer REFERENCES public.locations(id) ON DELETE CASCADE,
    CONSTRAINT explore_locations_pkey PRIMARY KEY (id)
);

ALTER TABLE public.explore_locations OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.explore_locations_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.explore_locations_id_seq OWNER TO postgres;
ALTER SEQUENCE public.explore_locations_id_seq OWNED BY public.explore_locations.id;
ALTER TABLE ONLY public.explore_locations ALTER COLUMN id SET DEFAULT nextval('public.explore_locations_id_seq'::regclass);

-- Explore lists junction
CREATE TABLE IF NOT EXISTS public.explore_lists (
    id integer NOT NULL,
    explore_id integer REFERENCES public.explore(id) ON DELETE CASCADE,
    list_id integer REFERENCES public.lists(id) ON DELETE CASCADE,
    CONSTRAINT explore_lists_pkey PRIMARY KEY (id)
);

ALTER TABLE public.explore_lists OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.explore_lists_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.explore_lists_id_seq OWNER TO postgres;
ALTER SEQUENCE public.explore_lists_id_seq OWNED BY public.explore_lists.id;
ALTER TABLE ONLY public.explore_lists ALTER COLUMN id SET DEFAULT nextval('public.explore_lists_id_seq'::regclass);

-- Explore posts junction
CREATE TABLE IF NOT EXISTS public.explore_posts (
    id integer NOT NULL,
    explore_id integer REFERENCES public.explore(id) ON DELETE CASCADE,
    post_id integer REFERENCES public.posts(id) ON DELETE CASCADE,
    CONSTRAINT explore_posts_pkey PRIMARY KEY (id)
);

ALTER TABLE public.explore_posts OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.explore_posts_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.explore_posts_id_seq OWNER TO postgres;
ALTER SEQUENCE public.explore_posts_id_seq OWNED BY public.explore_posts.id;
ALTER TABLE ONLY public.explore_posts ALTER COLUMN id SET DEFAULT nextval('public.explore_posts_id_seq'::regclass);

-- Explore products junction
CREATE TABLE IF NOT EXISTS public.explore_products (
    id integer NOT NULL,
    explore_id integer REFERENCES public.explore(id) ON DELETE CASCADE,
    product_id integer REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT explore_products_pkey PRIMARY KEY (id)
);

ALTER TABLE public.explore_products OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.explore_products_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.explore_products_id_seq OWNER TO postgres;
ALTER SEQUENCE public.explore_products_id_seq OWNED BY public.explore_products.id;
ALTER TABLE ONLY public.explore_products ALTER COLUMN id SET DEFAULT nextval('public.explore_products_id_seq'::regclass);

-- Explore profiles junction (was explore_users)
CREATE TABLE IF NOT EXISTS public.explore_profiles (
    id integer NOT NULL,
    explore_id integer REFERENCES public.explore(id) ON DELETE CASCADE,
    profile_id integer REFERENCES public.profiles(id) ON DELETE CASCADE,
    CONSTRAINT explore_profiles_pkey PRIMARY KEY (id)
);

ALTER TABLE public.explore_profiles OWNER TO postgres;

CREATE SEQUENCE IF NOT EXISTS public.explore_profiles_id_seq
    AS integer START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;
ALTER TABLE public.explore_profiles_id_seq OWNER TO postgres;
ALTER SEQUENCE public.explore_profiles_id_seq OWNED BY public.explore_profiles.id;
ALTER TABLE ONLY public.explore_profiles ALTER COLUMN id SET DEFAULT nextval('public.explore_profiles_id_seq'::regclass);
