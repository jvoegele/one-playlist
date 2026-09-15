CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

CREATE TABLE public.provider_connections (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL,
    provider text NOT NULL,
    -- 'supabase_identity': arrived via linkIdentity (Spotify, YouTube Music).
    -- 'own_flow': arrived via this app's own OAuth/PKCE or credentials form
    -- (TIDAL, Subsonic). Disconnect needs this to know whether an
    -- unlinkIdentity is owed.
    source text NOT NULL,
    -- The user's stable id at the provider, so a reconnect can be matched to
    -- the existing row even if the account's display name changes.
    provider_user_id text NOT NULL,
    display_name text,
    -- Only meaningful for a self-hosted Subsonic server; null for every other
    -- provider. Not a secret itself, so it isn't behind Vault like the tokens
    -- below are.
    server_url text,
    -- Bare ids into vault.secrets, not FKs yet: the function that actually
    -- writes secrets and populates these columns is a follow-up piece.
    access_token_secret_id uuid,
    refresh_token_secret_id uuid,
    access_token_expires_at timestamptz,
    scopes text[] NOT NULL DEFAULT '{}',
    status text NOT NULL DEFAULT 'active',
    last_refreshed_at timestamptz,
    last_error text,
    consecutive_failures integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.provider_connections
FOR EACH ROW
EXECUTE FUNCTION extensions.moddatetime(updated_at);

ALTER TABLE ONLY public.provider_connections
ADD CONSTRAINT provider_connections_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.provider_connections
ADD CONSTRAINT provider_connections_user_id_fkey
FOREIGN KEY (user_id) REFERENCES auth.users (id)
ON DELETE CASCADE;

ALTER TABLE ONLY public.provider_connections
ADD CONSTRAINT provider_connections_provider_check
CHECK (provider IN ('spotify', 'youtube_music', 'tidal', 'subsonic'));

ALTER TABLE ONLY public.provider_connections
ADD CONSTRAINT provider_connections_source_check
CHECK (source IN ('supabase_identity', 'own_flow'));

ALTER TABLE ONLY public.provider_connections
ADD CONSTRAINT provider_connections_status_check
CHECK (status IN ('active', 'expired', 'revoked', 'reauth_required'));

ALTER TABLE ONLY public.provider_connections
ADD CONSTRAINT provider_connections_server_url_scheme_check
CHECK (server_url IS NULL OR server_url ~* '^https?://');

CREATE INDEX provider_connections_user_id_index ON public.provider_connections
USING btree (user_id);

-- The refresh scheduler's query: "which connections expire soon?" Partial,
-- because it never looks at connections that aren't active.
CREATE INDEX provider_connections_refresh_due_index ON public.provider_connections
USING btree (access_token_expires_at)
WHERE (status = 'active');

-- One identity-linked connection per provider per user: Supabase Auth only
-- lets an account link one identity per provider, so Spotify and YouTube
-- Music inherit that limit here. Subsonic connections (source = 'own_flow')
-- are exempt on purpose — several servers per user is a real case.
CREATE UNIQUE INDEX provider_connections_one_identity_per_provider
ON public.provider_connections USING btree (user_id, provider)
WHERE (source = 'supabase_identity');

ALTER TABLE public.provider_connections ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.provider_connections FROM anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.provider_connections TO authenticated;
GRANT ALL ON public.provider_connections TO service_role;

CREATE POLICY provider_connections_owner_access ON public.provider_connections
FOR ALL
TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);
