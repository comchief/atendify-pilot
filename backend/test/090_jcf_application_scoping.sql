-- Regression test for fix #13: no JCF officer, for any division, could ever
-- see their own division's Noise Abatement filings (jcfApplication), the
-- documents attached to them (jcfApplicationFiles), or their division's
-- watch list entries (jcfWatchlist) — despite being able to log in and
-- manage their own roster (jcfdUser) just fine.
--
-- Two compounding causes, both fixed together:
--   a. atd_jcf_jurisdiction_muni_id() looked up a plain 'jcfBranch:{id}'
--      record for `linkedMuniId` — a record the app never actually writes
--      (linkedMuniId lives on the division's own agency:{id} record
--      instead) — so it always returned null, for every division, since
--      the original schema handoff.
--   b. jcfApplication/jcfApplicationFiles/jcfWatchlist were scoped by the
--      same key_part2-based policy as jcfBranch/jcfdUser, but key_part2 is
--      the appNumber or TRN for those three, never the branch id, so the
--      check could never match regardless of (a).
--
-- This test seeds two real JCF divisions (branch 5, linked to muni agency 1
-- / muniNumber 1; branch 7, linked to muni agency 2 / muniNumber 4) the way
-- reference_data_seed.sql actually does, then confirms a division's own
-- Chief can read and update their own jurisdiction's records while a
-- different division's Chief, the filing applicant, and anon are each
-- correctly scoped.

insert into public.kv_store (key, value) values
  ('agency:1', '{"id":1,"name":"Test Muni A","type":"Municipal Corporation","muniNumber":1}'::jsonb),
  ('agency:5', '{"id":5,"name":"Test JCF Branch 5","type":"JCF","linkedMuniId":1}'::jsonb),
  ('agency:2', '{"id":2,"name":"Test Muni B","type":"Municipal Corporation","muniNumber":4}'::jsonb),
  ('agency:7', '{"id":7,"name":"Test JCF Branch 7","type":"JCF","linkedMuniId":2}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into auth.users (id, email) values
  ('90000000-0000-0000-0000-000000000001', 'branch7.chief@jcf.gov.jm'),
  ('90000000-0000-0000-0000-000000000002', 'branch5.chief@jcf.gov.jm'),
  ('90000000-0000-0000-0000-000000000003', 'filing.applicant@example.com')
on conflict (email) do nothing;

insert into public.staff_invites (email, role, jcf_branch_id, display_name) values
  ('branch7.chief@jcf.gov.jm', 'jcfd', '7', 'Branch 7 Chief'),
  ('branch5.chief@jcf.gov.jm', 'jcfd', '5', 'Branch 5 Chief')
on conflict (email) do nothing;
update public.profiles set role = 'jcfd', jcf_branch_id = '7' where email = 'branch7.chief@jcf.gov.jm';
update public.profiles set role = 'jcfd', jcf_branch_id = '5' where email = 'branch5.chief@jcf.gov.jm';
update public.profiles set role = 'poa' where email = 'filing.applicant@example.com';

-- A filing against muniNumber 4 (branch 7's jurisdiction), with attached
-- files and one division-7 watch list entry.
insert into public.kv_store (key, value) values
  ('jcfApplication:TESTAPP-90-01', '{"jcfAppNumber":"TESTAPP-90-01","ownerEmail":"filing.applicant@example.com","muniId":4,"status":"Submitted"}'::jsonb),
  ('jcfApplicationFiles:TESTAPP-90-01', '{"photoIdFileData":"data:image/png;base64,test"}'::jsonb),
  ('jcfWatchlist:999888777', '{"trn":"999888777","agencyId":7,"fullName":"Test Watchlist Entry"}'::jsonb)
on conflict (key) do nothing;

-- ---- as branch 7's own Chief: this IS their jurisdiction ----
set role authenticated;
select set_config('atd_test.uid', '90000000-0000-0000-0000-000000000001', false);
select set_config('atd_test.email', 'branch7.chief@jcf.gov.jm', false);

select test_assert(
  public.atd_jcf_jurisdiction_muni_id() = '4',
  'atd_jcf_jurisdiction_muni_id() resolves branch 7 to muniNumber 4 (via agency:7 -> linkedMuniId 2 -> agency:2 -> muniNumber 4)'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplication:TESTAPP-90-01') = 1,
  'branch 7''s own Chief can read a jcfApplication filed in their jurisdiction'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplicationFiles:TESTAPP-90-01') = 1,
  'branch 7''s own Chief can read the attached files for that same filing'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfWatchlist:999888777') = 1,
  'branch 7''s own Chief can read their own division''s watchlist entry'
);

update public.kv_store set value = value || '{"status":"Under Review"}'::jsonb
  where key = 'jcfApplication:TESTAPP-90-01';
select test_assert(
  (select value->>'status' from public.kv_store where key = 'jcfApplication:TESTAPP-90-01') = 'Under Review',
  'branch 7''s own Chief can update a jcfApplication filed in their jurisdiction'
);

reset role;
select set_config('atd_test.uid', '', false);
select set_config('atd_test.email', '', false);

-- ---- as branch 5's Chief: a DIFFERENT division's jurisdiction ----
set role authenticated;
select set_config('atd_test.uid', '90000000-0000-0000-0000-000000000002', false);
select set_config('atd_test.email', 'branch5.chief@jcf.gov.jm', false);

select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplication:TESTAPP-90-01') = 0,
  'a different division''s Chief canNOT read a filing outside their own jurisdiction'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplicationFiles:TESTAPP-90-01') = 0,
  'a different division''s Chief canNOT read the attached files for that filing either'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfWatchlist:999888777') = 0,
  'a different division''s Chief canNOT read another division''s watchlist entry'
);

reset role;
select set_config('atd_test.uid', '', false);
select set_config('atd_test.email', '', false);

-- ---- as the applicant who filed it: their own filing's files ----
set role authenticated;
select set_config('atd_test.uid', '90000000-0000-0000-0000-000000000003', false);
select set_config('atd_test.email', 'filing.applicant@example.com', false);

select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplicationFiles:TESTAPP-90-01') = 1,
  'the applicant who filed it can read their own jcfApplicationFiles record'
);

reset role;
select set_config('atd_test.uid', '', false);
select set_config('atd_test.email', '', false);

-- ---- as anon: none of it ----
set role anon;
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplication:TESTAPP-90-01') = 0,
  'an anonymous caller canNOT read a jcfApplication record'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfApplicationFiles:TESTAPP-90-01') = 0,
  'an anonymous caller canNOT read a jcfApplicationFiles record'
);
reset role;
