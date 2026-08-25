-- Smoke test: after loading pg_stub.sql + supabase_schema.sql, the objects
-- every other test file depends on actually exist. Catches a schema file
-- that fails to apply cleanly before any RLS-specific test even runs.
select test_assert(to_regclass('public.kv_store') is not null, 'kv_store table exists');
select test_assert(to_regclass('public.profiles') is not null, 'profiles table exists');
select test_assert(to_regclass('public.staff_invites') is not null, 'staff_invites table exists');
select test_assert(to_regclass('public.login_attempts') is not null, 'login_attempts table exists');
select test_assert(
  (select count(*) from pg_proc where proname = 'atd_handle_new_user') = 1,
  'atd_handle_new_user trigger function exists'
);
select test_assert(
  (select count(*) from pg_proc where proname = 'atd_check_login_allowed') = 1,
  'atd_check_login_allowed function exists'
);
select test_assert(
  (select count(*) from pg_proc where proname = 'atd_record_login_attempt') = 1,
  'atd_record_login_attempt function exists'
);
select test_assert(
  (select count(*) from pg_proc where proname = 'atd_count_active_lockouts') = 1,
  'atd_count_active_lockouts function exists'
);
select test_assert(
  (select count(*) from pg_trigger where tgname = 'atd_on_auth_user_created') = 1,
  'atd_on_auth_user_created trigger is attached to auth.users'
);
