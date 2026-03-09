-- FaceLab Initial Database Schema
-- Run this in Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users profile table (extends Supabase Auth)
CREATE TABLE IF NOT EXISTS public.users (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Makeup Looks table
CREATE TABLE IF NOT EXISTS public.makeup_looks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    thumbnail_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Makeup Layers table (individual brush strokes per look)
CREATE TABLE IF NOT EXISTS public.makeup_layers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    look_id UUID REFERENCES public.makeup_looks(id) ON DELETE CASCADE NOT NULL,
    brush_type TEXT NOT NULL,  -- foundation, blush, eyeshadow, lipstick, contour, highlighter
    color_hex TEXT NOT NULL,   -- #RRGGBB
    opacity FLOAT DEFAULT 0.6,
    size FLOAT DEFAULT 0.5,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.makeup_looks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.makeup_layers ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own data
CREATE POLICY "Users can view own profile"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON public.users FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own looks"
    ON public.makeup_looks FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own looks"
    ON public.makeup_looks FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own looks"
    ON public.makeup_looks FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own looks"
    ON public.makeup_looks FOR DELETE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can view own layers"
    ON public.makeup_layers FOR SELECT
    USING (
        look_id IN (
            SELECT id FROM public.makeup_looks WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own layers"
    ON public.makeup_layers FOR INSERT
    WITH CHECK (
        look_id IN (
            SELECT id FROM public.makeup_looks WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete own layers"
    ON public.makeup_layers FOR DELETE
    USING (
        look_id IN (
            SELECT id FROM public.makeup_looks WHERE user_id = auth.uid()
        )
    );

-- Auto-create user profile on sign up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Storage bucket for face captures (create via Supabase Dashboard > Storage)
-- Bucket name: face-captures
-- Public: false
-- Allowed MIME types: image/jpeg, image/png
