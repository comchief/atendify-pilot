-- A few baseline RLS invariants not covered by the more specific regression
-- tests above — cheap to check, and exactly the kind of thing a future
-- change could quietly weaken without anyone noticing until a real user
-- does.

insert into auth.users (id, email) values
  ('60000000-0000-0000-0000-000000000001', 'person.a@example.com'),
  ('60000000-0000-0000-0000-000000000002', 'person.b@example.com');

set role authenticated;
select set_config('atd_test.uid', '60000000-0000-0000-0000-000000000001', false);
select set_config('atd_test.email', 'person.a@example.com', false);

select test_assert(
  (select count(*) from public.profiles where id = '60000000-0000-0000-0000-000000000001') = 1,
  'a signed-in user can read their own profile'
);
select test_assert(
  (select count(*) from public.profiles where id = '60000000-0000-0000-0000-000000000002') = 0,
  'a signed-in user canNOT read someone else''s profile'
);
select test_assert(
  (select count(*) from public.staff_invites) = 0,
  'a non-admin cannot read staff_invites at all'
);

reset role;

-- Clear the impersonated identity explicitly — it's a session-level
-- setting, not tied to role, so it would otherwise leak into the "anon"
-- block below and make this look like an authenticated request in
-- disguise instead of a genuinely anonymous one.
select set_config('atd_test.uid', '', false);
select set_config('atd_test.email', '', false);

set role anon;
select test_assert(
  (select count(*) from public.profiles) = 0,
  'an anonymous caller cannot read any profile'
);
select test_assert(
  (select count(*) from public.staff_invites) = 0,
  'an anonymous caller cannot read staff_invites'
);
reset role;
