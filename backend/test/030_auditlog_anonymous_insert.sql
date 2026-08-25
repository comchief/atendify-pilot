-- Regression test for the multi-round auditLog saga. Two distinct rules,
-- both load-bearing:
--   1. An anonymous 'login.failed' entry must insert successfully (the
--      fix — widened to allow this specific case without opening up
--      anonymous writes generally).
--   2. An anonymous entry for any OTHER action must still be rejected.
-- (The earlier, harder-to-see bug — that upsert's conflict check needs a
-- SELECT policy independent of INSERT — is a client-side fix in
-- atendify.html, not something this schema-level test can observe; the
-- fix there was switching audit writes to a plain insert.)

set role anon;

with ins as (
  insert into public.kv_store (key, value)
  values ('auditLog:test-anon-login-failed', '{"action":"login.failed","portal":"jcf","actor":"x@example.com"}'::jsonb)
  returning 1
)
select test_assert(
  (select count(*) from ins) = 1,
  'an anonymous login.failed audit entry inserts successfully'
);

select test_assert_raises(
  $q$insert into public.kv_store (key, value)
     values ('auditLog:test-anon-other-action', '{"action":"agency.create","portal":"admin"}'::jsonb)$q$,
  'an anonymous non-login.failed audit entry is rejected'
);

select test_assert(
  (select count(*) from public.kv_store where prefix = 'auditLog') = 0,
  'anon cannot read the audit log at all (admin-only select)'
);

reset role;
