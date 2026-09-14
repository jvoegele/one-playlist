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

-- psql variables: pure text substitution, done by psql itself before the SQL is
-- even sent to the server. `:'alice_id'` expands to a quoted, escaped literal
-- (like quote_literal), so it's safe to drop straight into a `values` list.
\set alice_id 11111111-1111-4111-8111-111111111111
\set bob_id 22222222-2222-4222-8222-222222222222

-- Two fake users, written straight into auth.users. Fine here: this is a test
-- fixture inside a doomed transaction, not a real sign-up.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values
(
    :'alice_id',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'alice@pgtap.test',
    now(),
    now()
),
(
    :'bob_id',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'bob@pgtap.test',
    now(),
    now()
);

-- One playlist each. id/created_at/updated_at all have defaults now, so they don't
-- need to be specified.
insert into public.library_playlists (user_id, name)
values
(:'alice_id', 'alice playlist'),
(:'bob_id', 'bob playlist');

-- ---------------------------------------------------------------------------
-- Helper functions, created in pg_temp (the session's private schema) so they
-- disappear along with everything else when this transaction rolls back.
-- ---------------------------------------------------------------------------

-- Makes the rest of the session look like a request from `user_id`, the way
-- PostgREST does it for Supabase: `authenticated` role, plus the JWT claims
-- that RLS policies read via `auth.uid()`.
create function pg_temp.as_user(user_id uuid) returns void
language plpgsql as $$
begin
    set local role authenticated;
    perform set_config(
        'request.jwt.claims',
        json_build_object('sub', user_id, 'role', 'authenticated')::text,
        true
    );
end;
$$;

-- Row count in library_playlists owned by p_user_id, under whatever
-- role/claims are currently in effect.
create function pg_temp.playlist_count_for(p_user_id uuid) returns integer
language sql as $$
    select count(*)::integer from public.library_playlists where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- 1. RLS is opt-in — assert it was opted into.
-- ---------------------------------------------------------------------------

select ok(
    (
        select relrowsecurity from pg_class
        where oid = 'public.library_playlists'::regclass
    ),
    'row level security is enabled on public.library_playlists'
);

-- ---------------------------------------------------------------------------
-- As Alice.
-- ---------------------------------------------------------------------------

select pg_temp.as_user(:'alice_id'::uuid);

-- 2. Alice sees only her own playlist, never Bob's. One results_eq replaces
-- what used to be two separate count() assertions.
select results_eq(
    'select user_id from public.library_playlists',
    array[:'alice_id'::uuid],
    'Alice sees only her own playlist'
);

-- 3. Alice can insert a playlist that belongs to her.
insert into public.library_playlists (user_id, name)
values (:'alice_id', 'Alice in Chains');

select is(
    pg_temp.playlist_count_for(:'alice_id'::uuid),
    2,
    'Alice can insert a playlist that belongs to her'
);

-- 4. Alice cannot insert a playlist that belongs to Bob.
select throws_ok(
    format(
        $$ insert into public.library_playlists (user_id, name)
           values (%L, 'Bob''s playlist') $$,
        :'bob_id'
    ),
    '42501',
    'new row violates row-level security policy for table "library_playlists"'
);

-- 5. Alice can update her own row, and the `updated_at` trigger actually fires.
insert into public.library_playlists (user_id, name, updated_at)
values (:'alice_id', 'alice2', '2000-01-01T00:00:00Z');

update public.library_playlists set name = 'alice2 updated'
where user_id = :'alice_id' and name = 'alice2';

select ok(
    (
        select updated_at > '2000-01-01T00:00:00Z'::timestamptz
        from public.library_playlists
        where user_id = :'alice_id' and name = 'alice2 updated'
    ),
    'updated_at was bumped by the trigger'
);

-- 6. Alice can delete her own rows.
delete from public.library_playlists
where user_id = :'alice_id';

select is(
    pg_temp.playlist_count_for(:'alice_id'::uuid),
    0,
    'Alice can delete her own rows'
);

-- 7. Updating Bob's row (naming it explicitly) affects zero rows.
update public.library_playlists set name = 'bob updated'
where user_id = :'bob_id' and name = 'bob playlist';

reset role;

select is(
    (
        select name from public.library_playlists
        where user_id = :'bob_id'
    ),
    'bob playlist',
    'Bob''s row was not updated by Alice'
);

select pg_temp.as_user(:'alice_id'::uuid);

-- 8. Deleting Bob's row (naming it explicitly) affects zero rows.
delete from public.library_playlists
where user_id = :'bob_id';

reset role;

select is(
    pg_temp.playlist_count_for(:'bob_id'::uuid),
    1,
    'Bob''s row was not deleted by Alice'
);

select set_config('request.jwt.claims', '', true);
reset role;

select * from finish();

rollback;
