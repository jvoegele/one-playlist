-- RLS for public.provider_connections, tested where it is actually enforced: in Postgres.
--
--     supabase test db
--
-- Everything runs inside a transaction that is rolled back, so the users and rows
-- created below never reach the database you're developing against.

begin;

create extension if not exists pgtap with schema extensions;

-- NOTE: this must match the exact number of assertions below, or `finish()` fails.
select plan(10);

-- Fixture users, created by tests.create_supabase_user() (from
-- 00000-supabase_test_helpers.sql, which runs before this file — see that
-- file for why the shared setup lives there and not in an \ir-included one).
-- `tests.get_supabase_uid('alice')` looks a row back up by its identifier
-- whenever we need the uuid below, so there's no local variable to track.
select tests.create_supabase_user('alice', 'alice@pgtap.test');
select tests.create_supabase_user('bob', 'bob@pgtap.test');

-- One connection each. id/created_at/updated_at all have defaults, so they
-- don't need to be specified.
insert into public.provider_connections (user_id, provider, source, provider_user_id)
values
(tests.get_supabase_uid('alice'), 'spotify', 'supabase_identity', 'alice-spotify-id'),
(tests.get_supabase_uid('bob'), 'spotify', 'supabase_identity', 'bob-spotify-id');

-- ---------------------------------------------------------------------------
-- Helper function local to this file, created in pg_temp (the session's
-- private schema) so it disappears along with everything else when this
-- transaction rolls back.
-- ---------------------------------------------------------------------------

-- Row count in provider_connections owned by p_user_id, under whatever
-- role/claims are currently in effect.
create function pg_temp.connection_count_for(p_user_id uuid) returns integer
language sql as $$
    select count(*)::integer from public.provider_connections where user_id = p_user_id;
$$;

-- ---------------------------------------------------------------------------
-- 1. RLS is opt-in — assert it was opted into.
-- ---------------------------------------------------------------------------

select tests.rls_enabled('public', 'provider_connections');

-- ---------------------------------------------------------------------------
-- As Alice.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('alice');

-- 2. Alice sees only her own connection, never Bob's. One results_eq replaces
-- what used to be two separate count() assertions.
select results_eq(
    'select user_id from public.provider_connections',
    array[tests.get_supabase_uid('alice')],
    'Alice sees only her own connection'
);

-- 3. Alice can insert a connection that belongs to her.
insert into public.provider_connections (user_id, provider, source, provider_user_id)
values (tests.get_supabase_uid('alice'), 'tidal', 'own_flow', 'alice-tidal-id');

select is(
    pg_temp.connection_count_for(tests.get_supabase_uid('alice')),
    2,
    'Alice can insert a connection that belongs to her'
);

-- 4. Alice cannot insert a connection that belongs to Bob.
select throws_ok(
    format(
        $$ insert into public.provider_connections (user_id, provider, source, provider_user_id)
           values (%L, 'tidal', 'own_flow', 'bobs-tidal-id') $$,
        tests.get_supabase_uid('bob')
    ),
    '42501',
    'new row violates row-level security policy for table "provider_connections"'
);

-- 5. Alice can update her own row, and the `updated_at` trigger actually fires.
insert into public.provider_connections (user_id, provider, source, provider_user_id, updated_at)
values (tests.get_supabase_uid('alice'), 'subsonic', 'own_flow', 'alice-subsonic-1', '2000-01-01T00:00:00Z');

update public.provider_connections set display_name = 'home server'
where user_id = tests.get_supabase_uid('alice') and provider_user_id = 'alice-subsonic-1';

select ok(
    (
        select updated_at > '2000-01-01T00:00:00Z'::timestamptz
        from public.provider_connections
        where user_id = tests.get_supabase_uid('alice') and provider_user_id = 'alice-subsonic-1'
    ),
    'updated_at was bumped by the trigger'
);

-- 6. Alice can have two Subsonic connections (several servers, both
-- source = 'own_flow') — the partial unique index doesn't apply to them.
insert into public.provider_connections (user_id, provider, source, provider_user_id)
values (tests.get_supabase_uid('alice'), 'subsonic', 'own_flow', 'alice-subsonic-2');

select is(
    pg_temp.connection_count_for(tests.get_supabase_uid('alice')),
    4,
    'Alice can have two Subsonic connections at once'
);

-- 7. But a second identity-linked Spotify connection for the same user
-- violates the partial unique index — Auth only lets one identity per
-- provider be linked at a time.
select throws_ok(
    format(
        $$ insert into public.provider_connections (user_id, provider, source, provider_user_id)
           values (%L, 'spotify', 'supabase_identity', 'alice-spotify-id-2') $$,
        tests.get_supabase_uid('alice')
    ),
    '23505',
    'duplicate key value violates unique constraint "provider_connections_one_identity_per_provider"'
);

-- 8. Alice can delete her own rows.
delete from public.provider_connections
where user_id = tests.get_supabase_uid('alice');

select is(
    pg_temp.connection_count_for(tests.get_supabase_uid('alice')),
    0,
    'Alice can delete her own rows'
);

-- 9. Updating Bob's row (naming it explicitly) affects zero rows.
update public.provider_connections set display_name = 'hijacked'
where user_id = tests.get_supabase_uid('bob') and provider = 'spotify';

reset role;

select is(
    (
        select display_name from public.provider_connections
        where user_id = tests.get_supabase_uid('bob')
    ),
    null,
    'Bob''s row was not updated by Alice'
);

select tests.authenticate_as('alice');

-- 10. Deleting Bob's row (naming it explicitly) affects zero rows.
delete from public.provider_connections
where user_id = tests.get_supabase_uid('bob');

reset role;

select is(
    pg_temp.connection_count_for(tests.get_supabase_uid('bob')),
    1,
    'Bob''s row was not deleted by Alice'
);

select tests.clear_authentication();
reset role;

select * from finish();

rollback;
