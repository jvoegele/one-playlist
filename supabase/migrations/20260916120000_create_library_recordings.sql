CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

-- Ownerless and shared: a recording is catalogue data, not anything a user
-- owns. Contrast library_playlist_items, which is a user's own account of a
-- track and links here only for catalogue facts (title, artists, ISRC...).
CREATE TABLE public.library_recordings (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    isrc text,
    title text NOT NULL,
    artists text[] NOT NULL DEFAULT '{}',
    album text,
    album_upc text,
    track_number integer,
    volume_number integer,
    version text,
    duration_seconds integer,
    explicit boolean,
    artwork_url text,
    origin_provider text,
    origin_provider_id text,
    -- True when more than one release disagrees about this recording's ISRC.
    -- Left as a plain flag rather than resolved here; domain.md §6.
    isrc_disputed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.library_recordings
FOR EACH ROW
EXECUTE FUNCTION extensions.moddatetime(updated_at);

ALTER TABLE ONLY public.library_recordings
ADD CONSTRAINT library_recordings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.library_recordings
ADD CONSTRAINT library_recordings_duration_check
CHECK (duration_seconds IS null OR duration_seconds >= 0);

CREATE INDEX library_recordings_isrc_index ON public.library_recordings
USING btree (isrc)
WHERE (isrc IS NOT null);

ALTER TABLE public.library_recordings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.library_recordings FROM anon, authenticated;

GRANT SELECT ON public.library_recordings TO authenticated;
GRANT ALL ON public.library_recordings TO service_role;

-- No user filter: every signed-in user reads the whole shared catalogue.
-- Nothing is granted to authenticated beyond SELECT, so there is no write
-- policy to write yet.
CREATE POLICY library_recordings_read_all ON public.library_recordings
FOR SELECT
TO authenticated
USING (true);
