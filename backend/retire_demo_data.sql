-- ============================================================================
-- Atendify — retiring the fictional demo agencies (hardening plan, Phase C)
-- ============================================================================
-- What this is: a reviewed, agency-by-agency removal script for the 8
-- fictional agency records that ship with this app (5 Municipal
-- Corporations + 3 JCF/JFB divisions attached to them) — invented staff,
-- applications, venues, and ads that the pilot-readiness report flagged as
-- needing to come out before real staff are working alongside them.
--
-- WHAT THIS DOES NOT DO: decide which agencies are ready to retire, or run
-- itself. That's the point of "one at a time, as each real one comes
-- online" from the hardening plan — this session has no access to your
-- live Supabase project, so nothing here has been run against production.
-- Every DELETE block below is written to be run by hand, one agency at a
-- time, only once you've confirmed its real replacement is actually live.
--
-- BEFORE RUNNING ANYTHING HERE: there is still no verified backup/recovery
-- path for this database (see SETUP.md / the pilot-readiness report — this
-- is still an open gap). Take a manual export first — in the Supabase
-- dashboard: Database → Backups, or run
--   select * from public.kv_store where prefix in ('agency','muniUser','jcfdUser','application','venue','adItem','jcfApplication','jcfApplicationFiles')
-- and download the result as CSV from the SQL editor — before deleting
-- anything below.
--
-- Scoping note, easy to get wrong: Municipal Corporation data (muniUser,
-- application, venue, adItem) is scoped by muniNumber, a separate field
-- from the agency's own id. JCF/JFB data (jcfdUser, jcfBranch) is scoped
-- by the agency's own id instead. The table below is the authoritative
-- mapping used throughout this script — don't substitute one number for
-- the other.
--
--   Agency                              agency id   muniNumber
--   Kingston & St. Andrew Muni Corp     1           1
--   St. Mary Municipal Corporation      2           4
--   St. James Municipal Corporation     3           7      (status: Suspended)
--   Manchester Municipal Corporation    4           11
--   Portmore Municipal Council          8           14
--   JCF — Noise Abatement Unit          5           n/a (linked to muni agency id 1)
--   Jamaica Fire Brigade                6           n/a (linked to muni agency id 1)
--   JCF — St. Mary Division             7           n/a (linked to muni agency id 2)
--
-- None of the 9 real Municipal Corporations added this week (agency ids
-- 9–17, blank contact info) are touched by anything in this file.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- STEP 0 — run this first, independent of any deletion: confirm the
-- invite-provisioning fix (SETUP.md's "ninth bug") has actually run for
-- every REAL CEO/Chief before touching anything the demo agencies might be
-- adjacent to. Any row returned here needs the backfill in SETUP.md before
-- you go further — an already-broken real account is the wrong thing to
-- be looking at for the first time while also mid-deletion.
-- ---------------------------------------------------------------------------
select
  (a.value->>'id')::int as agency_id,
  a.value->>'name' as name,
  a.value->>'type' as type,
  a.value->>'email' as ceo_or_chief_email,
  p.role as profile_role,
  case
    when p.role is null then 'has not signed up yet — fine, nothing to fix'
    when p.role = 'poa' then 'STUCK AS POA — needs the SETUP.md backfill before anything else'
    else 'ok (' || p.role || ')'
  end as status
from public.kv_store a
left join public.profiles p on lower(p.email) = lower(a.value->>'email')
where a.prefix = 'agency'
  and (a.value->>'id')::int not in (1,2,3,4,5,6,7,8) -- excludes the fictional agencies this file retires
order by (a.value->>'id')::int;


-- ============================================================================
-- PREVIEW — run this before any DELETE block below. Shows exactly what each
-- agency's removal would affect, without changing anything.
-- ============================================================================
select 'agency' as prefix, (value->>'id')::int as ref, count(*) from public.kv_store
  where prefix = 'agency' and (value->>'id')::int in (1,2,3,4,5,6,7,8) group by 1,2
union all
select 'muniUser', (value->>'muniId')::int, count(*) from public.kv_store
  where prefix = 'muniUser' and (value->>'muniId')::int in (1,4,7,11,14) group by 1,2
union all
select 'jcfdUser', key_part2::int, count(*) from public.kv_store
  where prefix = 'jcfdUser' and key_part2::int in (5,6,7) group by 1,2
union all
select 'application', (value->>'muniId')::int, count(*) from public.kv_store
  where prefix = 'application' and (value->>'muniId')::int in (1,4,7,11,14) group by 1,2
union all
select 'venue', (value->>'muniId')::int, count(*) from public.kv_store
  where prefix = 'venue' and (value->>'muniId')::int in (1,4,7,11,14) group by 1,2
union all
select 'adItem', (value->>'muniId')::int, count(*) from public.kv_store
  where prefix = 'adItem' and (value->>'muniId')::int in (1,4,7,11,14) group by 1,2
union all
select 'jcfBranch', key_part2::int, count(*) from public.kv_store
  where prefix = 'jcfBranch' and key_part2::int in (5,6,7) group by 1,2
order by 1, 2;


-- ============================================================================
-- Per-agency removal blocks. Each is self-contained and independent of the
-- others — retire one Municipal Corporation (and, where relevant, its
-- attached JCF/JFB division) only when its real replacement is confirmed
-- live and staffed. Every block is wrapped in a transaction so a mistake
-- rolls back cleanly instead of partially applying.
-- ============================================================================

-- ---- Kingston & St. Andrew (agency id 1, muniNumber 1) --------------------
-- Also retires its two attached agencies: JCF — Noise Abatement Unit (id 5)
-- and Jamaica Fire Brigade (id 6), since both exist only as this agency's
-- demo counterparts.
begin;
  delete from public.kv_store where prefix = 'jcfApplication' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 1
  );
  delete from public.kv_store where prefix = 'jcfApplicationFiles' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 1
  );
  delete from public.kv_store where prefix = 'application' and (value->>'muniId')::int = 1;
  delete from public.kv_store where prefix = 'venue' and (value->>'muniId')::int = 1;
  delete from public.kv_store where prefix = 'adItem' and (value->>'muniId')::int = 1;
  delete from public.kv_store where prefix = 'muniUser' and (value->>'muniId')::int = 1;
  delete from public.kv_store where prefix = 'jcfdUser' and key_part2 in ('5','6');
  delete from public.kv_store where prefix = 'jcfBranch' and key_part2 in ('5','6');
  delete from public.kv_store where prefix = 'agency' and (value->>'id')::int in (1,5,6);
  delete from public.staff_invites where email in (
    'andrea.powell@kmc.gov.jm','paul.bennett@kmc.gov.jm','sasha.grant@kmc.gov.jm',
    'rohan.blake@jcf.gov.jm','michelle.grant@jcf.gov.jm','andre.douglas@jcf.gov.jm','hwt.station@jcf.gov.jm'
  );
  -- Review the output above, then either COMMIT or ROLLBACK by hand —
  -- deliberately not auto-committed.
-- commit;

-- ---- St. Mary (agency id 2, muniNumber 4) ----------------------------------
-- Also retires its attached JCF — St. Mary Division (id 7).
begin;
  delete from public.kv_store where prefix = 'jcfApplication' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 4
  );
  delete from public.kv_store where prefix = 'jcfApplicationFiles' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 4
  );
  delete from public.kv_store where prefix = 'application' and (value->>'muniId')::int = 4;
  delete from public.kv_store where prefix = 'venue' and (value->>'muniId')::int = 4;
  delete from public.kv_store where prefix = 'adItem' and (value->>'muniId')::int = 4;
  delete from public.kv_store where prefix = 'muniUser' and (value->>'muniId')::int = 4;
  delete from public.kv_store where prefix = 'jcfdUser' and key_part2 = '7';
  delete from public.kv_store where prefix = 'jcfBranch' and key_part2 = '7';
  delete from public.kv_store where prefix = 'agency' and (value->>'id')::int in (2,7);
  delete from public.staff_invites where email in (
    'marlon.reid@stmary.gov.jm','tanya.ford@stmary.gov.jm','richard.dunn@stmary.gov.jm',
    'paula.grant@jcf.gov.jm','kemar.wilson@jcf.gov.jm','portmaria.station@jcf.gov.jm'
  );
-- commit;

-- ---- St. James / Montego Bay (agency id 3, muniNumber 7) -------------------
-- Already shows status "Suspended" in the demo data — no attached JCF/JFB
-- division of its own (the real St. James JCF division you created live is
-- a SEPARATE agency record from this one and is never touched by this
-- file).
begin;
  delete from public.kv_store where prefix = 'jcfApplication' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 7
  );
  delete from public.kv_store where prefix = 'jcfApplicationFiles' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 7
  );
  delete from public.kv_store where prefix = 'application' and (value->>'muniId')::int = 7;
  delete from public.kv_store where prefix = 'venue' and (value->>'muniId')::int = 7;
  delete from public.kv_store where prefix = 'adItem' and (value->>'muniId')::int = 7;
  delete from public.kv_store where prefix = 'muniUser' and (value->>'muniId')::int = 7;
  delete from public.kv_store where prefix = 'agency' and (value->>'id')::int = 3;
  delete from public.staff_invites where email in (
    'kerryann.blake@mobay.gov.jm','odain.clarke@mobay.gov.jm','michelle.barrett@mobay.gov.jm'
  );
-- commit;

-- ---- Manchester (agency id 4, muniNumber 11) -------------------------------
begin;
  delete from public.kv_store where prefix = 'jcfApplication' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 11
  );
  delete from public.kv_store where prefix = 'jcfApplicationFiles' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 11
  );
  delete from public.kv_store where prefix = 'application' and (value->>'muniId')::int = 11;
  delete from public.kv_store where prefix = 'venue' and (value->>'muniId')::int = 11;
  delete from public.kv_store where prefix = 'adItem' and (value->>'muniId')::int = 11;
  delete from public.kv_store where prefix = 'muniUser' and (value->>'muniId')::int = 11;
  delete from public.kv_store where prefix = 'agency' and (value->>'id')::int = 4;
  delete from public.staff_invites where email in (
    'devon.hylton@manchester.gov.jm','sherika.palmer@manchester.gov.jm','andre.lawson@manchester.gov.jm'
  );
-- commit;

-- ---- Portmore (agency id 8, muniNumber 14) ---------------------------------
begin;
  delete from public.kv_store where prefix = 'jcfApplication' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 14
  );
  delete from public.kv_store where prefix = 'jcfApplicationFiles' and key_part2 in (
    select regexp_replace(key, '^application:', '') from public.kv_store
    where prefix = 'application' and (value->>'muniId')::int = 14
  );
  delete from public.kv_store where prefix = 'application' and (value->>'muniId')::int = 14;
  delete from public.kv_store where prefix = 'venue' and (value->>'muniId')::int = 14;
  delete from public.kv_store where prefix = 'adItem' and (value->>'muniId')::int = 14;
  delete from public.kv_store where prefix = 'muniUser' and (value->>'muniId')::int = 14;
  delete from public.kv_store where prefix = 'agency' and (value->>'id')::int = 8;
  delete from public.staff_invites where email in ('portmore.admin@gov.jm');
-- commit;

-- ============================================================================
-- Deliberately not touched by this file:
--   - auditLog entries referencing these agencies — kept as history rather
--     than erased, even for a retired demo agency.
--   - the shared national watchlist (watchlist:{trn}) — not agency-scoped,
--     applies across every agency.
--   - files already uploaded to the application-files storage bucket for
--     these demo applications — deleting the kv_store row does not delete
--     the underlying object. Harmless (no RLS/security exposure, just a
--     few orphaned files) but worth a separate Storage-console cleanup
--     pass later if it matters.
--   - any of the 9 real Municipal Corporations added this week (agency ids
--     9–17) or any agency you've created live since (including the real
--     St. James JCF division) — none of those ids appear anywhere above.
-- ============================================================================
