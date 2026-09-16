-- place_entry moves one library_playlist_item to a new spot within its
-- playlist. This is the project's first rpc function — see the
-- conversation in docs/learning-log.md for why a Postgres function, not a
-- few .update() calls from a Server Action: several rows may need their
-- position changed together, and that has to be one transaction or the
-- playlist's ordering can end up corrupted partway through.
--
-- Signature: the caller names what was dropped and where, never a whole
-- new ordering (port-plan.md §13). "Where" is relative to another entry —
-- p_after_entry_id — rather than a raw index, so the client never needs to
-- know how positions are stored internally:
--
--   place_entry(p_entry_id, p_after_entry_id => some_other_entry.id)
--   place_entry(p_entry_id, p_after_entry_id => NULL)  -- move to the front
--
-- SECURITY INVOKER (the default for a function — no need to write it, it's
-- called out here as a reminder): this runs as the calling user, so every
-- statement inside it is still filtered by library_playlist_items' existing
-- RLS policy. That's why there's no SECURITY DEFINER here, unlike e.g. the
-- Vault-writing function in port-plan.md §8 — this function isn't doing
-- anything the caller isn't already allowed to do directly; it's just
-- bundling several such things into one transaction.
--
-- Positions are gap-based integers (100, 200, 300, ...): moving an entry
-- usually means giving it the midpoint of its two new neighbors' positions,
-- a single-row write. When two neighbors are adjacent integers, there's no
-- midpoint to give it, so the whole playlist is renumbered back to evenly
-- spaced values instead (see the ELSE branch below).
CREATE OR REPLACE FUNCTION public.place_entry(
    p_entry_id uuid,
    p_after_entry_id uuid  -- NULL means "move to the very front"
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    -- The standard spacing new positions are given, whether by the
    -- fast-path midpoint or by a full renumber. Not load-bearing on its
    -- own — just keeps the "gap" numbers below in agreement with each
    -- other.
    c_gap CONSTANT integer := 100;

    v_playlist_id uuid;
    v_after_playlist_id uuid;

    -- The midpoint calculation's floor and ceiling: the new position ends
    -- up strictly between these two. v_lower_bound is p_after_entry_id's
    -- own position (or 0, for "move to the front"). v_upper_bound is
    -- whatever currently sits immediately after that anchor (or a fresh
    -- value, if the anchor is currently last, or the playlist's only
    -- other entry). Previously named v_after_entry_pos / v_before_entry_pos
    -- — renamed because "before/after" described the *entries*, not what
    -- these values actually do in the arithmetic below, and the two kept
    -- reading as opposites of what they meant.
    v_lower_bound integer;
    v_upper_bound integer;

    v_new_position integer;
BEGIN
    -- Sanity check: don't let the caller try to move an entry after itself.
    -- That would be a no-op, but it could also indicate a bug in the caller's logic.
    IF p_entry_id = p_after_entry_id THEN
        RAISE EXCEPTION 'cannot move entry % after itself', p_entry_id;
    END IF;

    -- ------------------------------------------------------------------
    -- 1. Look up the entry being moved.
    --
    -- This SELECT runs as the caller, so it's already filtered by
    -- library_playlist_items_owner_access — if p_entry_id doesn't belong
    -- to the caller, this simply finds no row, and the exception below
    -- fires. Ownership enforcement is free here; there's no need to
    -- separately check auth.uid() = user_id in this function's own body.
    -- ------------------------------------------------------------------
    SELECT playlist_id INTO v_playlist_id
    FROM public.library_playlist_items
    WHERE id = p_entry_id;

    IF v_playlist_id IS NULL THEN
        RAISE EXCEPTION 'entry % not found', p_entry_id;
    END IF;

    -- ------------------------------------------------------------------
    -- Lock every row in this playlist before reading any of their
    -- positions. Without this, two concurrent moves in the same playlist
    -- (two tabs, a retried request) could each read the same "current"
    -- neighbor positions, then both write — silently clobbering one of the
    -- two moves, or both computing the same midpoint. FOR UPDATE makes a
    -- second, concurrent call to this function block here until the
    -- first one's transaction finishes, rather than racing on stale reads.
    -- ------------------------------------------------------------------
    PERFORM 1
    FROM public.library_playlist_items
    WHERE playlist_id = v_playlist_id
    FOR UPDATE;

    -- ------------------------------------------------------------------
    -- 2. Ensure that the entry we're moving and the entry we're moving it after
    -- are in the same playlist.
    -- ------------------------------------------------------------------
    IF p_after_entry_id IS NOT NULL THEN
        SELECT playlist_id INTO v_after_playlist_id
        FROM public.library_playlist_items
        WHERE id = p_after_entry_id;

        IF v_after_playlist_id IS NULL OR v_after_playlist_id <> v_playlist_id THEN
            RAISE EXCEPTION 'after-entry % is not in the same playlist as entry %', p_after_entry_id, p_entry_id;
        END IF;
    END IF;

    -- ------------------------------------------------------------------
    -- 3. Find the positions of the neighboring items and compute a new position
    -- for the moved item.
    -- ------------------------------------------------------------------
    IF p_after_entry_id IS NULL THEN
        v_lower_bound := 0;

        SELECT MIN(position) INTO v_upper_bound
        FROM public.library_playlist_items
        WHERE playlist_id = v_playlist_id AND id <> p_entry_id;

        IF v_upper_bound IS NULL THEN
            -- The entry being moved is the only item in the playlist.
            -- 2 * c_gap here (not c_gap) so the midpoint below lands
            -- exactly c_gap away from zero, matching the spacing every
            -- other position in the table uses.
            v_upper_bound := 2 * c_gap;
        END IF;
    ELSE
        SELECT position INTO v_lower_bound
        FROM public.library_playlist_items
        WHERE id = p_after_entry_id;

        SELECT MIN(position) INTO v_upper_bound
        FROM public.library_playlist_items
        WHERE playlist_id = v_playlist_id AND id <> p_entry_id AND position > v_lower_bound;

        IF v_upper_bound IS NULL THEN
            -- The entry is being moved to the end of the playlist — same
            -- 2 * c_gap reasoning as above.
            v_upper_bound := v_lower_bound + 2 * c_gap;
        END IF;
    END IF;

    IF v_upper_bound - v_lower_bound > 1 THEN
        -- Room for an integer strictly between the two neighbors: the
        -- common case, a single-row write.
        v_new_position := (v_lower_bound + v_upper_bound) / 2;

        UPDATE public.library_playlist_items
        SET position = v_new_position
        WHERE id = p_entry_id;
    ELSE
        -- v_lower_bound and v_upper_bound are adjacent integers — no room
        -- to give the moved entry its own position without touching
        -- every other row. Renumber the whole playlist instead:
        -- reproduce its current order, with the moved entry spliced into
        -- its new spot, and hand every row a fresh, evenly spaced
        -- position in one statement.
        --
        -- The splice is done with a sort key rather than an insertion
        -- index computed by hand: every other entry sorts by its own
        -- current position; the moved entry gets a fractional key
        -- (v_lower_bound + 0.5) guaranteed to land strictly between its
        -- new neighbors, because v_lower_bound and v_upper_bound above
        -- were already computed as exactly those neighbors. ORDER BY does
        -- the rest, and row_number() turns that order straight into
        -- gapped integer positions.
        WITH ordered AS (
            SELECT id, ROW_NUMBER() OVER (ORDER BY sort_key) AS rank_in_playlist
            FROM (
                SELECT id, position::numeric AS sort_key
                FROM public.library_playlist_items
                WHERE playlist_id = v_playlist_id AND id <> p_entry_id

                UNION ALL

                SELECT p_entry_id, v_lower_bound + 0.5
            ) AS current_and_moved
        )
        UPDATE public.library_playlist_items AS item
        SET position = ordered.rank_in_playlist * c_gap
        FROM ordered
        WHERE item.id = ordered.id;
    END IF;
END;
$$;

-- Functions need the same explicit-grant treatment as tables, and for the
-- same reason: Supabase's platform sets up default privileges that grant
-- EXECUTE on every new public-schema function to anon, authenticated, and
-- service_role automatically (see pg_default_acl). REVOKE ALL FROM PUBLIC
-- only undoes the plain-Postgres default (grant to the PUBLIC pseudo-role);
-- it does nothing to those already-materialized per-role grants, so the
-- REVOKE has to name anon and authenticated explicitly, exactly like every
-- table migration in this project already does.
REVOKE ALL ON FUNCTION public.place_entry(uuid, uuid) FROM public, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.place_entry(uuid, uuid) TO authenticated, service_role;
