CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

-- An entry in a user's playlist. It carries its own account of the track
-- (title, artists, album, ...) rather than reading those through
-- recording_id, so a bad or missing match never destroys what the user
-- actually put in the playlist. recording_id supplies catalogue facts only,
-- and is nullable: a recording can be unmatched, or its match removed later.
CREATE TABLE public.library_playlist_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    playlist_id uuid NOT NULL,
    -- Denormalized from library_playlists.user_id so RLS below can filter
    -- without a join. See the WITH CHECK clause for why that's not enough
    -- on its own.
    user_id uuid NOT NULL,
    recording_id uuid,
    position integer NOT NULL,
    title text NOT NULL,
    artists text[] NOT NULL DEFAULT '{}',
    album text,
    version text,
    duration_seconds integer,
    isrc text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.library_playlist_items
FOR EACH ROW
EXECUTE FUNCTION extensions.moddatetime(updated_at);

ALTER TABLE ONLY public.library_playlist_items
ADD CONSTRAINT library_playlist_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_playlist_items
ADD CONSTRAINT library_playlist_items_playlist_id_fkey
FOREIGN KEY (playlist_id) REFERENCES public.library_playlists (id)
ON DELETE CASCADE;

ALTER TABLE ONLY public.library_playlist_items
ADD CONSTRAINT library_playlist_items_user_id_fkey
FOREIGN KEY (user_id) REFERENCES auth.users (id)
ON DELETE CASCADE;

ALTER TABLE ONLY public.library_playlist_items
ADD CONSTRAINT library_playlist_items_recording_id_fkey
FOREIGN KEY (recording_id) REFERENCES public.library_recordings (id)
ON DELETE SET NULL;

ALTER TABLE ONLY public.library_playlist_items
ADD CONSTRAINT library_playlist_items_duration_check
CHECK (duration_seconds IS NULL OR duration_seconds >= 0);

-- Covers "this playlist's items, in order" (the read every page does) and,
-- as a prefix, "this playlist's items" alone.
CREATE INDEX library_playlist_items_playlist_id_position_index
ON public.library_playlist_items USING btree (playlist_id, position);

ALTER TABLE public.library_playlist_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.library_playlist_items FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.library_playlist_items TO authenticated;
GRANT ALL ON public.library_playlist_items TO service_role;

CREATE POLICY library_playlist_items_owner_access ON public.library_playlist_items
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
        SELECT 1 FROM public.library_playlists AS p
        WHERE p.id = library_playlist_items.playlist_id
            AND p.user_id = library_playlist_items.user_id
    )
);
