-- Regression test for fix #7/#10: five specific one-time "have I already
-- seeded my demo/reference data" flags live in the admin-only 'platform'
-- prefix, but need to be readable by an anonymous visitor (every page load
-- checks them before deciding whether to write seed data) without opening
-- up the rest of that prefix. Missing even one of the five reproduces the
-- exact "new row violates row-level security policy for table kv_store"
-- noise reported multiple times this engagement.

insert into public.kv_store (key, value) values
  ('platform:agenciesSeeded', 'true'),
  ('platform:muniUsersSeeded', 'true'),
  ('platform:demoDataSeeded', 'true'),
  ('platform:rolesSeeded', 'true'),
  ('platform:jcfdUsersSeeded', 'true'),
  ('platform:securityPolicy', '{"maxFailedAttempts":5}'::jsonb) -- NOT one of the 5 — must stay admin-only
on conflict (key) do update set value = excluded.value;

set role anon;

select test_assert(
  (select value from public.kv_store where key = 'platform:agenciesSeeded') = 'true',
  'anon can read platform:agenciesSeeded'
);
select test_assert(
  (select value from public.kv_store where key = 'platform:muniUsersSeeded') = 'true',
  'anon can read platform:muniUsersSeeded'
);
select test_assert(
  (select value from public.kv_store where key = 'platform:demoDataSeeded') = 'true',
  'anon can read platform:demoDataSeeded'
);
select test_assert(
  (select value from public.kv_store where key = 'platform:rolesSeeded') = 'true',
  'anon can read platform:rolesSeeded'
);
select test_assert(
  (select value from public.kv_store where key = 'platform:jcfdUsersSeeded') = 'true',
  'anon can read platform:jcfdUsersSeeded (the flag fix #7 originally missed)'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'platform:securityPolicy') = 0,
  'anon canNOT read platform:securityPolicy — only the 5 named flags are exempt from admin-only'
);

reset role;
