-- RLS for public.library_recordings, tested where it is actually enforced: in
-- Postgres.
--
--     supabase test db
--
-- Everything runs inside a transaction that is rolled back, so the users and
-- rows created below never reach the database you're developing against.

begin;

create extension if not exists pgtap with schema extensions;

select plan(5);

select tests.create_supabase_user('alice', 'alice@pgtap.test');
select tests.create_supabase_user('bob', 'bob@pgtap.test');

-- Seeded as service_role, since no role can insert through RLS yet — this is
-- the shared catalogue, not anyone's row.
insert into public.library_recordings (title, artists, isrc)
values ('Ænima', array['Tool'], 'USTC49500001');

-- ---------------------------------------------------------------------------
-- 1. RLS is opt-in — assert it was opted into.
-- ---------------------------------------------------------------------------

select tests.rls_enabled('public', 'library_recordings');

-- ---------------------------------------------------------------------------
-- As Alice.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('alice');

-- 2. Alice sees the shared recording, though she didn't create it and it has
-- no user_id to filter on.
select results_eq(
    'select title from public.library_recordings',
    array['Ænima'],
    'Alice sees the shared recording'
);

-- 3. Bob sees the very same row.
select tests.authenticate_as('bob');

select results_eq(
    'select title from public.library_recordings',
    array['Ænima'],
    'Bob sees the same shared recording'
);

-- 4. Alice cannot insert into the catalogue: authenticated has no INSERT
-- grant at all, so this fails before RLS even gets a say.
select tests.authenticate_as('alice');

select throws_ok(
    $$ insert into public.library_recordings (title) values ('New Recording') $$,
    '42501',
    'permission denied for table library_recordings'
);

-- 5. Nor can she update the one that exists.
select throws_ok(
    $$ update public.library_recordings set title = 'Retitled' $$,
    '42501',
    'permission denied for table library_recordings'
);

select tests.clear_authentication();
reset role;

select * from finish();

rollback;
