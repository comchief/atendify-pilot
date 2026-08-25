-- Regression test for fix #11 — the more serious, proactively-discovered
-- bug behind this engagement's auditLog investigation: applicants (poa)
-- had insert+select on their own applications, but no update policy, so an
-- application's first save succeeded (nothing to conflict with) but the
-- SAME application's next save — paying a fee, uploading a document, any
-- later wizard step — failed once it genuinely conflicted. Every write in
-- this app is an upsert (INSERT ... ON CONFLICT DO UPDATE), which needs an
-- applicable UPDATE policy for the DO UPDATE branch to succeed.

insert into auth.users (id, email) values
  ('20000000-0000-0000-0000-000000000001', 'applicant.one@example.com'),
  ('20000000-0000-0000-0000-000000000002', 'applicant.two@example.com');
-- Neither has a staff_invites row, so both correctly land as 'poa'.

set role authenticated;
select set_config('atd_test.uid', '20000000-0000-0000-0000-000000000001', false);
select set_config('atd_test.email', 'applicant.one@example.com', false);

with ins as (
  insert into public.kv_store (key, value)
  values ('application:POA-TEST-1', '{"ownerEmail":"applicant.one@example.com","status":"Submitted"}'::jsonb)
  returning 1
)
select test_assert(
  (select count(*) from ins) = 1,
  'an applicant can create their own application (first save, insert-only path)'
);

with upd as (
  insert into public.kv_store (key, value)
  values ('application:POA-TEST-1', '{"ownerEmail":"applicant.one@example.com","status":"Paid"}'::jsonb)
  on conflict (key) do update set value = excluded.value
  returning 1
)
select test_assert(
  (select count(*) from upd) = 1,
  'the SAME applicant can genuinely re-save their own application (the actual fix #11 regression case)'
);
select test_assert(
  (select value->>'status' from public.kv_store where key = 'application:POA-TEST-1') = 'Paid',
  'the re-save actually persisted the new value'
);

reset role;

-- A different applicant must still be unable to touch someone else's
-- application — fix #11 must not have widened access, only added the
-- missing case for one's OWN records.
set role authenticated;
select set_config('atd_test.uid', '20000000-0000-0000-0000-000000000002', false);
select set_config('atd_test.email', 'applicant.two@example.com', false);

select test_assert_raises(
  $q$insert into public.kv_store (key, value)
     values ('application:POA-TEST-1', '{"ownerEmail":"applicant.one@example.com","status":"Hijacked"}'::jsonb)
     on conflict (key) do update set value = excluded.value$q$,
  'a different applicant cannot re-save someone else''s application'
);

reset role;
