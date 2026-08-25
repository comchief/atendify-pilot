-- Regression test for the actual bug behind "every stuck login" (fix #4):
-- atd_handle_new_user used to check `if inv is not null`, which Postgres
-- only treats as true when EVERY column of the composite is non-null — and
-- every real staff_invites row has at least one null column by design (a
-- muni invite has no jcf_branch_id, etc). That silently sent every
-- pre-authorized signup down the "no invite, default to poa" branch. Fixed
-- to check a single not-null column instead; this test signs up two
-- accounts — one WITH a matching invite, one WITHOUT — and asserts each
-- lands in the right role.

insert into public.staff_invites (email, role, jcf_branch_id, display_name)
values ('officer.invited@jcf.gov.jm', 'jcfd', '5', 'Test Officer')
on conflict (email) do nothing;

-- Signing up with a matching invite should assign the invited role/branch,
-- not fall through to 'poa'.
insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'officer.invited@jcf.gov.jm');

select test_assert(
  (select role from public.profiles where email = 'officer.invited@jcf.gov.jm') = 'jcfd',
  'a signup matching a staff_invites row is assigned that role, not poa'
);
select test_assert(
  (select jcf_branch_id from public.profiles where email = 'officer.invited@jcf.gov.jm') = '5',
  'the invited jcf_branch_id carries over onto the profile'
);

-- Signing up with NO matching invite must default to a public applicant —
-- this is the correct, intentional behavior for a real applicant signup,
-- and the regression case for the original bug (this branch is exactly
-- the one every invited signup was wrongly falling into).
insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000002', 'no.invite@example.com');

select test_assert(
  (select role from public.profiles where email = 'no.invite@example.com') = 'poa',
  'a signup with no matching invite correctly lands as a public applicant'
);
