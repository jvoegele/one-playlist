-- RLS for public.library_playlists, tested where it is actually enforced: in Postgres.
--
--     supabase test db
--
-- Everything runs inside a transaction that is rolled back, so the users and rows
-- created below never reach the database you're developing against.

begin;

create extension if not exists pgtap with schema extensions;

-- NOTE: this must match the exact number of assertions below, or `finish()` fails.
select plan(9);

-- Two fake users, written straight into auth.users. Fine here: this is a test
-- fixture inside a doomed transaction, not a real sign-up.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values
(
    '11111111-1111-4111-8111-111111111111',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'alice@pgtap.test',
    now(),
    now()
),
(
    '22222222-2222-4222-8222-222222222222',
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
('11111111-1111-4111-8111-111111111111', 'alice playlist'),
('22222222-2222-4222-8222-222222222222', 'bob playlist');

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

set local role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true
);

select is(
    (select count(*)::integer from public.library_playlists),
    1,
    'Alice sees only her own playlist'
);

select is(
    (
        select count(*)::integer from public.library_playlists
        where user_id = '22222222-2222-4222-8222-222222222222'
    ),
    0,
    'Alice sees no playlists belonging to Bob'
);

-- 4. Alice can insert a playlist that belongs to her.
insert into public.library_playlists (user_id, name)
values ('11111111-1111-4111-8111-111111111111', 'Alice in Chains');

select is(
    (
        select count(*)::integer from public.library_playlists
        where user_id = '11111111-1111-4111-8111-111111111111'
    ),
    2,
    'Alice can insert a playlist that belongs to her'
);

-- 5. Alice cannot insert a playlist that belongs to Bob.
select throws_ok(
    $$ insert into public.library_playlists (user_id, name)
       values ('22222222-2222-4222-8222-222222222222', 'Bob''s playlist') $$,
    '42501',
    'new row violates row-level security policy for table "library_playlists"'
);

-- 6. Alice can update her own row, and the `updated_at` trigger actually fires.
insert into public.library_playlists (user_id, name, updated_at)
values
('11111111-1111-4111-8111-111111111111', 'alice2', '2000-01-01T00:00:00Z');

update public.library_playlists set name = 'alice2 updated'
where user_id = '11111111-1111-4111-8111-111111111111'
    and name = 'alice2';

select ok(
    (
        select updated_at > '2000-01-01T00:00:00Z'::timestamptz
        from public.library_playlists
        where user_id = '11111111-1111-4111-8111-111111111111'
            and name = 'alice2 updated'
    ),
    'updated_at was bumped by the trigger'
);

-- 7. Alice can delete her own rows.
delete from public.library_playlists
where user_id = '11111111-1111-4111-8111-111111111111';

select is(
    (
        select count(*)::integer from public.library_playlists
        where user_id = '11111111-1111-4111-8111-111111111111'
    ),
    0,
    'Alice can delete her own rows'
);

-- 8. Updating Bob's row (naming it explicitly) affects zero rows.
update public.library_playlists set name = 'bob updated'
where user_id = '22222222-2222-4222-8222-222222222222'
    and name = 'bob playlist';

reset role;

select is(
    (
        select name from public.library_playlists
        where user_id = '22222222-2222-4222-8222-222222222222'
    ),
    'bob playlist',
    'Bob''s row was not updated by Alice'
);

set local role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true
);

-- 9. Deleting Bob's row (naming it explicitly) affects zero rows.
delete from public.library_playlists
where user_id = '22222222-2222-4222-8222-222222222222';

reset role;

select is(
    (
        select count(*)::integer from public.library_playlists
        where user_id = '22222222-2222-4222-8222-222222222222'
    ),
    1,
    'Bob''s row was not deleted by Alice'
);

select set_config('request.jwt.claims', '', true);
reset role;

select * from finish();

rollback;
