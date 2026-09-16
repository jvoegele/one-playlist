-- Tests for public.place_entry(uuid, uuid), tested where it's actually
-- exercised: as a real Postgres function call, not by inspecting its body.
--
--     supabase test db
--
-- Everything runs inside a transaction that is rolled back, so the users
-- and rows created below never reach the database you're developing
-- against.
--
-- Not covered here: the row locking (FOR UPDATE) added for concurrent
-- calls. pgTAP runs single-session, so there's no way to exercise two
-- overlapping transactions from one test file.

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

select tests.create_supabase_user('alice', 'alice@pgtap.test');
select tests.create_supabase_user('bob', 'bob@pgtap.test');

-- ---------------------------------------------------------------------------
-- Fixture data. Fixed ids throughout, for the same reason as
-- library_playlist_items.test.sql: a lookup done while authenticated as
-- Alice would itself be filtered by RLS, so anything Alice needs to refer
-- to that isn't hers has to be a literal, not a subquery.
--
-- Playlist 1 (alice): A(100), B(200), C(300) — the fast-path (midpoint)
-- cases and the guard checks.
-- Playlist 2 (alice): X(10), Y(11), Z(12) — positions one apart on
-- purpose, so a single move has no room for a midpoint and forces the
-- renumbering branch deterministically, without needing several moves to
-- exhaust a gap.
-- Playlist 3 (bob): D(100) — the cross-playlist and ownership checks.
-- ---------------------------------------------------------------------------

insert into public.library_playlists (id, user_id, name)
values
('10000000-0000-0000-0000-000000000001', tests.get_supabase_uid('alice'), 'alice playlist 1'),
('20000000-0000-0000-0000-000000000001', tests.get_supabase_uid('alice'), 'alice playlist 2'),
('30000000-0000-0000-0000-000000000001', tests.get_supabase_uid('bob'), 'bob playlist');

insert into public.library_playlist_items (id, playlist_id, user_id, position, title)
values
(
    '10000000-0000-0000-0000-00000000000a',
    '10000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('alice'),
    100,
    'A'
),
(
    '10000000-0000-0000-0000-00000000000b',
    '10000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('alice'),
    200,
    'B'
),
(
    '10000000-0000-0000-0000-00000000000c',
    '10000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('alice'),
    300,
    'C'
),
(
    '20000000-0000-0000-0000-00000000000a',
    '20000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('alice'),
    10,
    'X'
),
(
    '20000000-0000-0000-0000-00000000000b',
    '20000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('alice'),
    11,
    'Y'
),
(
    '20000000-0000-0000-0000-00000000000c',
    '20000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('alice'),
    12,
    'Z'
),
(
    '30000000-0000-0000-0000-00000000000d',
    '30000000-0000-0000-0000-000000000001',
    tests.get_supabase_uid('bob'),
    100,
    'D'
);

-- ---------------------------------------------------------------------------
-- 1-2. Grants: authenticated and service_role can call this function; anon
-- cannot. (This is the pair of checks that caught the REVOKE ALL FROM
-- PUBLIC bug — anon had EXECUTE by default from Supabase's own
-- ALTER DEFAULT PRIVILEGES on the public schema, until the function's own
-- grants named anon explicitly.)
-- ---------------------------------------------------------------------------

select ok(
    has_function_privilege('authenticated', 'public.place_entry(uuid, uuid)', 'EXECUTE'),
    'authenticated can call place_entry'
);

select ok(
    not has_function_privilege('anon', 'public.place_entry(uuid, uuid)', 'EXECUTE'),
    'anon cannot call place_entry'
);

select tests.authenticate_as('alice');

-- ---------------------------------------------------------------------------
-- 3-5. The fast path: two moves, each with room for a midpoint.
-- ---------------------------------------------------------------------------

-- 3. Move C to the front. Neighbors are 0 (the floor) and A's 100, so C
-- lands at the midpoint, 50.
select public.place_entry('10000000-0000-0000-0000-00000000000c', null);

select is(
    (
        select position from public.library_playlist_items
        where id = '10000000-0000-0000-0000-00000000000c'
    ),
    50,
    'moving C to the front gives it the midpoint of 0 and A''s position'
);

-- 4. Move A to right after (the now-relocated) C. Neighbors are C's 50 and
-- B's 200, so A lands at 125.
select public.place_entry('10000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000c');

select is(
    (
        select position from public.library_playlist_items
        where id = '10000000-0000-0000-0000-00000000000a'
    ),
    125,
    'moving A after C gives it the midpoint of C''s and B''s positions'
);

-- 5. The resulting order is C, A, B — confirms the two moves above didn't
-- just get the right positions in isolation, but the right order overall.
select results_eq(
    'select title from public.library_playlist_items
     where playlist_id = ''10000000-0000-0000-0000-000000000001'' order by position',
    array['C', 'A', 'B'],
    'final order after both moves is C, A, B'
);

-- ---------------------------------------------------------------------------
-- 6-10. Guards. All of these raise plain RAISE EXCEPTIONs, which default
-- to SQLSTATE P0001.
-- ---------------------------------------------------------------------------

-- 6. Can't move an entry after itself.
select throws_ok(
    $$ select public.place_entry('10000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a') $$,
    'P0001',
    'cannot move entry 10000000-0000-0000-0000-00000000000a after itself'
);

-- 7. Can't move into a playlist that isn't the entry's own — after-entry
-- exists, but belongs to Bob.
select throws_ok(
    $$ select public.place_entry('10000000-0000-0000-0000-00000000000a', '30000000-0000-0000-0000-00000000000d') $$,
    'P0001',
    'after-entry 30000000-0000-0000-0000-00000000000d is not in the same playlist '
    || 'as entry 10000000-0000-0000-0000-00000000000a'
);

-- 8. The entry being moved doesn't exist (or isn't Alice's — RLS makes
-- those look identical from here, which is the point: see test 10).
select throws_ok(
    $$ select public.place_entry('99999999-9999-9999-9999-999999999999', null) $$,
    'P0001',
    'entry 99999999-9999-9999-9999-999999999999 not found'
);

-- 9. The after-entry doesn't exist at all — same error as test 7, because
-- "not found" and "found but in the wrong playlist" both fail the same
-- IS NULL OR <> check.
select throws_ok(
    $$ select public.place_entry(
        '10000000-0000-0000-0000-00000000000a', '99999999-9999-9999-9999-999999999999'
    ) $$,
    'P0001',
    'after-entry 99999999-9999-9999-9999-999999999999 is not in the same playlist '
    || 'as entry 10000000-0000-0000-0000-00000000000a'
);

-- 10. Ownership: Alice can't move Bob's entry. She can't see it at all
-- under RLS, so this fails the exact same way as test 8 (entry not found)
-- rather than a separate permission error — ownership enforcement is free
-- here, from the table's own RLS, not something this function checks
-- itself.
select throws_ok(
    $$ select public.place_entry('30000000-0000-0000-0000-00000000000d', null) $$,
    'P0001',
    'entry 30000000-0000-0000-0000-00000000000d not found'
);

-- ---------------------------------------------------------------------------
-- 11-12. The renumbering path: X(10), Y(11), Z(12) leaves no integer
-- between any two of them, so moving Z to right after X has no midpoint to
-- give it, and the whole playlist gets renumbered.
-- ---------------------------------------------------------------------------

select public.place_entry('20000000-0000-0000-0000-00000000000c', '20000000-0000-0000-0000-00000000000a');

-- 11. Order is preserved (and the move applied): X, Z, Y.
select results_eq(
    'select title from public.library_playlist_items
     where playlist_id = ''20000000-0000-0000-0000-000000000001'' order by position',
    array['X', 'Z', 'Y'],
    'renumbering preserves order with the moved entry spliced into its new spot'
);

-- 12. And the new positions are actually evenly spaced (100, 200, 300),
-- not just "in the right order" — confirms the renumbering branch ran
-- instead of, say, silently succeeding at a degenerate midpoint.
select results_eq(
    'select position from public.library_playlist_items
     where playlist_id = ''20000000-0000-0000-0000-000000000001'' order by position',
    array[100, 200, 300],
    'renumbering gives every item a fresh, evenly spaced position'
);

select tests.clear_authentication();
reset role;

select * from finish();

rollback;
