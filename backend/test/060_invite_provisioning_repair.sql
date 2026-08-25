-- Regression test for the "actual, still-open cause of the JCF login
-- report" bug: a newly-provisioned CEO/Chief who signs up with no
-- staff_invites row on file lands as a public applicant ('poa') instead of
-- their real role. atdProvisionMuniCeo/atdProvisionJcfdChief now write that
-- invite themselves at agency-creation time (a client-side fix, not
-- observable here) — but for any agency created before that fix, or any
-- other case where an invite is added AFTER a person already signed up,
-- the retroactive repair (fix #6's UPDATE, extracted below as its own
-- reusable step) must correctly heal the stuck profile once the invite
-- exists. This test reproduces both the break and the repair, exactly as
-- verified live against a local Postgres instance during this engagement.

insert into auth.users (id, email) values
  ('40000000-0000-0000-0000-000000000001', 'stjames.division@jcf.gov.jm');

select test_assert(
  (select role from public.profiles where email = 'stjames.division@jcf.gov.jm') = 'poa',
  'signing up with no invite on file lands as poa (reproduces the reported symptom)'
);

-- The one-off backfill an operator runs for an already-affected agency.
insert into public.staff_invites (email, role, jcf_branch_id, display_name)
values ('stjames.division@jcf.gov.jm', 'jcfd', '99', 'St. James Division')
on conflict (email) do update
  set role = excluded.role, jcf_branch_id = excluded.jcf_branch_id, display_name = excluded.display_name;

-- Fix #6's retroactive repair, verbatim logic (see phase1b_migration.sql).
update public.profiles p
set role = si.role, agency_id = si.agency_id, jcf_branch_id = si.jcf_branch_id,
    permissions = si.permissions, display_name = coalesce(p.display_name, si.display_name)
from public.staff_invites si
where lower(p.email) = lower(si.email) and p.role = 'poa';

select test_assert(
  (select role from public.profiles where email = 'stjames.division@jcf.gov.jm') = 'jcfd',
  'backfilling the invite and re-running the repair heals the stuck profile'
);
select test_assert(
  (select jcf_branch_id from public.profiles where email = 'stjames.division@jcf.gov.jm') = '99',
  'the repair also assigns the correct branch id'
);

-- The other, more common path: invite exists BEFORE signup (this is what
-- the client-side fix now does automatically for every new agency).
insert into public.staff_invites (email, role, agency_id, display_name)
values ('new.ceo@freshmuni.gov.jm', 'muni', '200', 'Fresh Muni CEO')
on conflict (email) do nothing;
insert into auth.users (id, email) values
  ('40000000-0000-0000-0000-000000000002', 'new.ceo@freshmuni.gov.jm');

select test_assert(
  (select role from public.profiles where email = 'new.ceo@freshmuni.gov.jm') = 'muni',
  'an invite created before signup assigns the right role directly — no repair step needed'
);
