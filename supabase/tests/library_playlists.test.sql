-- RLS for public.library_playlists, tested where it is actually enforced: in Postgres.
--
--     supabase test db
--
-- Everything runs inside a transaction that is rolled back, so the users and rows
-- created below never reach the database you're developing against.

begin;

create extension if not exists pgtap with schema extensions;

-- NOTE: this must match the exact number of assertions below, or `finish()` fails.
select plan(8);

-- Fixture users, created by tests.create_supabase_user() (from
-- 00000-supabase_test_helpers.sql, which runs before this file — see that
-- file for why the shared setup lives there and not in an \ir-included one).
-- `tests.get_supabase_uid('alice')` looks a row back up by its identifier
-- whenever we need the uuid below, so there's no local variable to track.
select tests.create_supabase_user('alice', 'alice@pgtap.test');
select tests.create_supabase_user('bob', 'bob@pgtap.test');

-- One playlist each. id/created_at/updated_at all have defaults now, so they don't
-- need to be specified.
insert into public.library_playlists (user_id, name)
values
(tests.get_supabase_uid('alice'), 'alice playlist'),
(tests.get_supabase_uid('bob'), 'bob playlist');

-- ---------------------------------------------------------------------------
-- Helper function local to this file, created in pg_temp (the session's
-- private schema) so it disappears along with everything else when this
-- transaction rolls back.
-- ---------------------------------------------------------------------------

-- Row count in library_playlists owned by p_user_id, under whatever
-- role/claims are currently in effect.
create function pg_temp.playlist_count_for(p_user_id uuid) returns integer
language sql as $$
    select count(*)::integer from public.library_playlists where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- 1. RLS is opt-in — assert it was opted into.
-- ---------------------------------------------------------------------------

select tests.rls_enabled('public', 'library_playlists');

-- ---------------------------------------------------------------------------
-- As Alice.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('alice');

-- 2. Alice sees only her own playlist, never Bob's. One results_eq replaces
-- what used to be two separate count() assertions.
select results_eq(
    'select user_id from public.library_playlists',
    array[tests.get_supabase_uid('alice')],
    'Alice sees only her own playlist'
);

-- 3. Alice can insert a playlist that belongs to her.
insert into public.library_playlists (user_id, name)
values (tests.get_supabase_uid('alice'), 'Alice in Chains');

select is(
    pg_temp.playlist_count_for(tests.get_supabase_uid('alice')),
    2,
    'Alice can insert a playlist that belongs to her'
);

-- 4. Alice cannot insert a playlist that belongs to Bob.
select throws_ok(
    format(
        $$ insert into public.library_playlists (user_id, name)
           values (%L, 'Bob''s playlist') $$,
        tests.get_supabase_uid('bob')
    ),
    '42501',
    'new row violates row-level security policy for table "library_playlists"'
);

-- 5. Alice can update her own row, and the `updated_at` trigger actually fires.
insert into public.library_playlists (user_id, name, updated_at)
values (tests.get_supabase_uid('alice'), 'alice2', '2000-01-01T00:00:00Z');

update public.library_playlists set name = 'alice2 updated'
where user_id = tests.get_supabase_uid('alice') and name = 'alice2';

select ok(
    (
        select updated_at > '2000-01-01T00:00:00Z'::timestamptz
        from public.library_playlists
        where user_id = tests.get_supabase_uid('alice') and name = 'alice2 updated'
    ),
    'updated_at was bumped by the trigger'
);

-- 6. Alice can delete her own rows.
delete from public.library_playlists
where user_id = tests.get_supabase_uid('alice');

select is(
    pg_temp.playlist_count_for(tests.get_supabase_uid('alice')),
    0,
    'Alice can delete her own rows'
);

-- 7. Updating Bob's row (naming it explicitly) affects zero rows.
update public.library_playlists set name = 'bob updated'
where user_id = tests.get_supabase_uid('bob') and name = 'bob playlist';

reset role;

select is(
    (
        select name from public.library_playlists
        where user_id = tests.get_supabase_uid('bob')
    ),
    'bob playlist',
    'Bob''s row was not updated by Alice'
);

select tests.authenticate_as('alice');

-- 8. Deleting Bob's row (naming it explicitly) affects zero rows.
delete from public.library_playlists
where user_id = tests.get_supabase_uid('bob');

reset role;

select is(
    pg_temp.playlist_count_for(tests.get_supabase_uid('bob')),
    1,
    'Bob''s row was not deleted by Alice'
);

select tests.clear_authentication();
reset role;

select * from finish();

rollback;
