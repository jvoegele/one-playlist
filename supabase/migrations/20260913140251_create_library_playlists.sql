CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

CREATE TABLE public.library_playlists (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.library_playlists
FOR EACH ROW
EXECUTE FUNCTION extensions.moddatetime(updated_at);

ALTER TABLE ONLY public.library_playlists
ADD CONSTRAINT library_playlists_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_playlists
ADD CONSTRAINT library_playlists_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE;

CREATE INDEX library_playlists_user_id_index ON public.library_playlists USING btree (user_id);

ALTER TABLE public.library_playlists ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.library_playlists FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.library_playlists TO authenticated;
GRANT ALL ON public.library_playlists TO service_role;

CREATE POLICY library_playlists_owner_access ON public.library_playlists
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);
