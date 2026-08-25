-- Regression test for fix #12 (server-side login lockout) — including the
-- exact NULL-comparison bug this test suite would have caught automatically
-- instead of relying on catching it by hand: the first version of
-- atd_count_active_lockouts() checked `if atd_role() <> 'admin'`, and
-- since atd_role() returns NULL for a caller with no profile row at all,
-- `NULL <> 'admin'` evaluates to NULL — which `if NULL then` in PL/pgSQL
-- silently falls through on, letting the least-trusted possible caller
-- reach the real count. This is the file whose absence let that bug ship
-- once already; it now exists specifically so it can't ship a second time.

insert into public.kv_store (key, value) values ('platform:securityPolicy', '{"maxFailedAttempts":3,"lockoutMinutes":15}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into auth.users (id, email) values ('50000000-0000-0000-0000-000000000001', 'admin@gmail.com')
on conflict (email) do nothing;
-- admin@gmail.com is pre-authorized to 'admin' by the seed insert already in supabase_schema.sql.

insert into auth.users (id, email) values ('50000000-0000-0000-0000-000000000002', 'nonadmin.poa@example.com')
on conflict (email) do nothing;
-- No invite -> lands as 'poa'.

set role anon;

select test_assert(
  (public.atd_check_login_allowed('jcf', 'chief@jcf.gov.jm')->>'allowed')::boolean = true,
  'no attempts yet -- login allowed'
);

select public.atd_record_login_attempt('jcf', 'chief@jcf.gov.jm', false);
select public.atd_record_login_attempt('jcf', 'chief@jcf.gov.jm', false);
select test_assert(
  (public.atd_check_login_allowed('jcf', 'chief@jcf.gov.jm')->>'allowed')::boolean = true,
  '2 failures, threshold is 3 -- still allowed'
);

select public.atd_record_login_attempt('jcf', 'chief@jcf.gov.jm', false);
select test_assert(
  (public.atd_check_login_allowed('jcf', 'chief@jcf.gov.jm')->>'allowed')::boolean = false,
  '3rd failure crosses the threshold -- now locked out'
);
select test_assert(
  (public.atd_check_login_allowed('jcf', 'chief@jcf.gov.jm')->>'message') like '%15 minute%',
  'the lockout message reflects the configured lockout duration'
);

select test_assert(
  (public.atd_check_login_allowed('muni', 'chief@jcf.gov.jm')->>'allowed')::boolean = true,
  'the SAME email in a different portal is unaffected -- lockouts are scoped per portal+email'
);

-- A success clears the counter outright.
select public.atd_record_login_attempt('muni', 'reset.me@example.com', false);
select public.atd_record_login_attempt('muni', 'reset.me@example.com', false);
select public.atd_record_login_attempt('muni', 'reset.me@example.com', true);
select test_assert(
  (public.atd_check_login_allowed('muni', 'reset.me@example.com')->>'allowed')::boolean = true,
  'a successful login clears the failure counter'
);

-- Direct table access must still be impossible — the lockout mechanism
-- only works if this table can't be read or rewritten around the two
-- functions above.
select test_assert(
  (select count(*) from public.login_attempts) = 0,
  'anon reading login_attempts directly sees 0 rows regardless of content -- RLS with no policies'
);
select test_assert_raises(
  $q$insert into public.login_attempts (portal, email) values ('jcf', 'bypass@example.com')$q$,
  'anon writing login_attempts directly is rejected'
);

reset role;

-- The actual regression case: atd_count_active_lockouts() must return 0
-- for a caller with NO profile row (truly anonymous) — this is exactly the
-- case the NULL-comparison bug got wrong.
set role anon;
select test_assert(
  public.atd_count_active_lockouts() = 0,
  'atd_count_active_lockouts() returns 0 for anon with no profile at all (the actual bug this test exists for)'
);
reset role;

-- ...and for an authenticated NON-admin caller.
set role authenticated;
select set_config('atd_test.uid', '50000000-0000-0000-0000-000000000002', false);
select test_assert(
  public.atd_count_active_lockouts() = 0,
  'atd_count_active_lockouts() returns 0 for an authenticated non-admin (poa) caller'
);
reset role;

-- ...and only an actual admin sees the real count (>= 1, since chief@jcf.gov.jm is locked above).
set role authenticated;
select set_config('atd_test.uid', '50000000-0000-0000-0000-000000000001', false);
select test_assert(
  public.atd_count_active_lockouts() >= 1,
  'atd_count_active_lockouts() returns the real count only for an authenticated admin'
);
reset role;
