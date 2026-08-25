-- Regression test for fix #8: JCF officer/Chief records (jcfdUser:...) are
-- manageable by a division's own signed-in staff, scoped to their own
-- branch only — this is the backend half of the JCF login/dropdown fix;
-- without 'jcfdUser' in this policy family, a JCF officer's own real login
-- (which re-reads their branch's roster right after signing in) hit an RLS
-- wall reading their own division's staff.

insert into public.staff_invites (email, role, jcf_branch_id, display_name) values
  ('branch5.officer@jcf.gov.jm', 'jcfd', '5', 'Branch 5 Officer'),
  ('branch7.officer@jcf.gov.jm', 'jcfd', '7', 'Branch 7 Officer')
on conflict (email) do nothing;

insert into auth.users (id, email) values
  ('30000000-0000-0000-0000-000000000001', 'branch5.officer@jcf.gov.jm'),
  ('30000000-0000-0000-0000-000000000002', 'branch7.officer@jcf.gov.jm');

set role authenticated;
select set_config('atd_test.uid', '30000000-0000-0000-0000-000000000001', false);
select set_config('atd_test.email', 'branch5.officer@jcf.gov.jm', false);

with ins as (
  insert into public.kv_store (key, value)
  values ('jcfdUser:5:1', '{"agencyId":5,"name":"Branch 5 Officer","role":"Officer","status":"Active"}'::jsonb)
  returning 1
)
select test_assert(
  (select count(*) from ins) = 1,
  'a JCF officer can write their own branch''s jcfdUser record'
);
select test_assert(
  (select count(*) from public.kv_store where key = 'jcfdUser:5:1') = 1,
  'a JCF officer can read their own branch''s jcfdUser record'
);
select test_assert(
  (select count(*) from public.kv_store where prefix = 'jcfdUser' and key_part2 = '7') = 0,
  'a JCF officer canNOT see a different branch''s jcfdUser records'
);

reset role;
