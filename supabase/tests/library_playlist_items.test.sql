-- RLS for public.library_playlist_items, tested where it is actually
-- enforced: in Postgres.
--
--     supabase test db
--
-- Everything runs inside a transaction that is rolled back, so the users and
-- rows created below never reach the database you're developing against.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

select tests.create_supabase_user('alice', 'alice@pgtap.test');
select tests.create_supabase_user('bob', 'bob@pgtap.test');

-- Fixed ids, not looked up later by name: a lookup done while authenticated
-- as Alice would itself be filtered by library_playlists' own RLS, so
-- selecting Bob's playlist id "as Alice" would silently come back NULL
-- instead of exercising the check below.
insert into public.library_playlists (id, user_id, name)
values
('22222222-2222-2222-2222-222222222222', tests.get_supabase_uid('alice'), 'alice playlist'),
('33333333-3333-3333-3333-333333333333', tests.get_supabase_uid('bob'), 'bob playlist');

insert into public.library_recordings (id, title, artists)
values ('11111111-1111-1111-1111-111111111111', 'Schism', array['Tool']);

insert into public.library_playlist_items (playlist_id, user_id, recording_id, position, title, artists)
values (
    '22222222-2222-2222-2222-222222222222',
    tests.get_supabase_uid('alice'),
    '11111111-1111-1111-1111-111111111111',
    0,
    'Schism',
    array['Tool']
);

insert into public.library_playlist_items (playlist_id, user_id, position, title)
values ('33333333-3333-3333-3333-333333333333', tests.get_supabase_uid('bob'), 0, 'bob''s track');

-- ---------------------------------------------------------------------------
-- 1. RLS is opt-in — assert it was opted into.
-- ---------------------------------------------------------------------------

select tests.rls_enabled('public', 'library_playlist_items');

-- ---------------------------------------------------------------------------
-- As Alice.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('alice');

-- 2. Alice sees only her own item, never Bob's.
select results_eq(
    'select title from public.library_playlist_items',
    array['Schism'],
    'Alice sees only her own item'
);

-- 3. Alice can insert another item into her own playlist.
insert into public.library_playlist_items (playlist_id, user_id, position, title)
values ('22222222-2222-2222-2222-222222222222', tests.get_supabase_uid('alice'), 1, 'Forty Six & 2');

select is(
    (
        select count(*)::integer from public.library_playlist_items
        where user_id = tests.get_supabase_uid('alice')
    ),
    2,
    'Alice can insert into her own playlist'
);

-- 4. Alice cannot insert a row claiming to be Bob, even into her own
-- playlist — the plain auth.uid() = user_id half of the check.
select throws_ok(
    format(
        $$ insert into public.library_playlist_items (playlist_id, user_id, "position", title)
           values ('22222222-2222-2222-2222-222222222222', %L, 2, 'sneaky') $$,
        tests.get_supabase_uid('bob')
    ),
    '42501',
    'new row violates row-level security policy for table "library_playlist_items"'
);

-- 5. Alice cannot insert a row into Bob's playlist even while correctly
-- claiming her own user_id — the EXISTS half of the check, which is the
-- reason it's not just auth.uid() = user_id.
select throws_ok(
    format(
        $$ insert into public.library_playlist_items (playlist_id, user_id, "position", title)
           values ('33333333-3333-3333-3333-333333333333', %L, 2, 'sneaky') $$,
        tests.get_supabase_uid('alice')
    ),
    '42501',
    'new row violates row-level security policy for table "library_playlist_items"'
);

-- 6. Alice can update her own row, and the updated_at trigger fires.
update public.library_playlist_items set updated_at = '2000-01-01T00:00:00Z'
where title = 'Schism';

update public.library_playlist_items set title = 'Schism (Live)'
where title = 'Schism';

select ok(
    (
        select updated_at > '2000-01-01T00:00:00Z'::timestamptz from public.library_playlist_items
        where title = 'Schism (Live)'
    ),
    'updated_at was bumped by the trigger'
);

-- 7. Alice can delete her own row.
delete from public.library_playlist_items
where title = 'Schism (Live)';

select is(
    (
        select count(*)::integer from public.library_playlist_items
        where title = 'Schism (Live)'
    ),
    0,
    'Alice can delete her own row'
);

-- 8. Updating Bob's row (naming it explicitly) affects zero rows.
update public.library_playlist_items set title = 'hijacked'
where title = 'bob''s track';

reset role;

select is(
    (
        select title from public.library_playlist_items
        where user_id = tests.get_supabase_uid('bob')
    ),
    'bob''s track',
    'Bob''s row was not updated by Alice'
);

-- ---------------------------------------------------------------------------
-- 9. recording_id follows ON DELETE SET NULL, not a cascade — deleting the
-- shared recording leaves Alice's remaining item in place, just unlinked.
-- Done as the reset-to-superuser role above: nothing in `authenticated` can
-- write to library_recordings at all (see its own test file).
-- ---------------------------------------------------------------------------

delete from public.library_recordings
where id = '11111111-1111-1111-1111-111111111111';

select is(
    (
        select recording_id from public.library_playlist_items
        where title = 'Forty Six & 2'
    ),
    null,
    'recording_id was set null, not the item deleted, when its recording was removed'
);

select tests.clear_authentication();
reset role;

select * from finish();

rollback;
