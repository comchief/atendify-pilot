-- ============================================================================
-- Atendify — Phase 1b migration
-- ============================================================================
-- Run this ONLY if you already ran supabase_schema.sql once on your project
-- (from the original backend hand-off). It applies just what changed for the
-- login/Auth rewrite:
--   1. Pre-authorizes the Admin account so its first real signup is assigned
--      the admin role.
--   2. Fixes 4 policies that scope an applicant to their own POA/JCF filings
--      — they originally checked a field (ownerUserId) the app never
--      actually writes; the app's real ownership field is ownerEmail, so
--      these are corrected to match it.
--   3. Fixes kv_store.updated_by's foreign key so deleting a user (e.g. a
--      test account you're cleaning up, or someone leaving the pilot) no
--      longer fails with "Database error deleting user" — that error was
--      Postgres blocking the delete because some kv_store row still pointed
--      at that user's id with no delete action defined. This changes it to
--      null out that "who touched this last" reference instead of blocking
--      deletion; it never touches the row's actual data.
--   4. Fixes a real bug in the trigger that's supposed to assign a
--      pre-authorized role at signup: it checked "if inv is not null" on the
--      whole staff_invites row, but Postgres only treats a composite value as
--      NOT NULL when every one of its columns is non-null — and every real
--      invite has at least one null column by design (a muni invite has no
--      jcf_branch_id, a jcfd invite has no agency_id, the admin invite has
--      neither). That made the condition false for every invite that ever
--      existed, so EVERY pre-authorized signup — admin included — silently
--      fell through to the "no invite, treat as public applicant" branch.
--      This is what caused the Admin login issue several steps back, and the
--      same thing happening now to every Municipal CEO/officer.
--   5. Pre-authorizes every officer/CEO already seeded in the app's demo/
--      pilot data (so far, only the platform Admin was pre-authorized).
--   6. Retroactively repairs any account that already signed up and got
--      stuck as a public applicant ('poa') because of bug #4 above — the
--      exact symptom you just saw with the Municipal CEO logins.
--   7. Adds a narrow public-read policy for 4 specific kv_store keys —
--      platform:agenciesSeeded, platform:muniUsersSeeded,
--      platform:demoDataSeeded, platform:rolesSeeded. These are just
--      boolean/timestamp "have I already loaded my one-time seed data"
--      markers the app checks before writing its agency directory, officer
--      roster, demo venues/ads/watchlist, and role templates — but they
--      live in the admin-only 'platform' prefix, so nobody but admin could
--      even READ them, meaning the check always came back empty and the
--      app retried the (RLS-blocked) write on every page load, forever, for
--      every visitor. Harmless in effect (falls back to local data) but
--      noisy — this is the "new row violates row-level security policy for
--      table kv_store" you kept seeing in the logs even though the agency
--      you created saved correctly. Run reference_data_seed.sql (updated,
--      see below) after this so those 4 flags are actually true in the
--      database and the checks succeed instead of retrying.
--   8. Adds 'jcfdUser' to the JCF-scoped records policy. JCF officer/Chief
--      accounts (unlike Municipal officers) never got a real, persisted
--      backend record at all — they lived only in the browser's own memory,
--      which is why a newly created JCF division never showed up in the
--      JCF portal's own login dropdown: nothing ever provisioned it a real,
--      shared officer record the way a new Municipal Corporation
--      automatically gets a CEO. This policy lets a division's own signed-in
--      staff manage jcfdUser:{branchId}:{id} records the same way they
--      already manage jcfBranch/jcfApplication records; admin's own
--      unconditional access already covers writing new ones at agency-
--      creation time. Run reference_data_seed.sql (updated, see below)
--      after this to load the 7 already-seeded JCF officers into it.
--   9. Widens the audit log insert policy so a FAILED login attempt can
--      actually be recorded. A failed login is, by definition, not signed
--      in — auth.uid() is null for it — so the original "must be signed in
--      to append" check silently rejected every login.failed entry with an
--      RLS violation, losing exactly the security-relevant record (repeated
--      failed logins) a government pilot's audit trail most needs. Now also
--      allows an anonymous append specifically when the record's own action
--      is 'login.failed'; every other action still requires a real session.
--  10. Adds a 5th key, platform:jcfdUsersSeeded, to fix #7's public-read
--      policy — missed when fix #8 added the JCF officer roster, so a JCF
--      officer's own real login (which re-reads that roster — see
--      atdLoadJcfdUsers()) kept hitting the exact same "can't even read the
--      flag, so retries the doomed write" RLS noise fix #7 was meant to
--      solve, just for this one new flag.
--  11. Adds the missing "poa updates own applications" / "poa updates own
--      jcf filings" policies. This is the actual root cause behind the
--      recurring "new row violates row-level security policy for table
--      kv_store" reports: every write in this app goes through an upsert
--      (INSERT ... ON CONFLICT DO UPDATE), and Postgres requires an
--      applicable UPDATE policy to perform the DO UPDATE branch whenever a
--      genuine conflict occurs — an INSERT policy alone only covers a
--      brand-new key. Applicants (poa) had insert+select for their own
--      applications/JCF filings but no update policy at all, so an
--      application's very FIRST save succeeded (nothing to conflict with
--      yet) but every later re-save of that SAME application — paying a
--      fee, uploading a document, any subsequent wizard step — would have
--      failed with this exact error the moment it genuinely conflicted.
--      Confirmed by reproducing the failure locally: a non-conflicting
--      upsert succeeds with only insert+select, a genuinely conflicting one
--      does not until an update policy exists too. (Separately, the
--      auditLog RLS noise turned out to be a related but distinct cause —
--      upsert also needs a SELECT policy just to check for a conflict, and
--      auditLog's SELECT policy is deliberately admin-only; fixed in
--      atendify.html by writing audit entries with a plain insert instead
--      of an upsert, since every audit key is always brand new.)
--  12. Moves login lockout enforcement server-side. It previously lived in
--      a kv_store prefix ('loginAttempts') deliberately left open to anon
--      read/write, on the reasoning that attempt counts aren't sensitive —
--      but that also meant any client could read, rewrite, or simply delete
--      its own lockout counter by calling the Supabase REST API directly,
--      bypassing this app's JS (and the lockout) entirely. Replaces that
--      policy with a dedicated table that has row level security enabled
--      and NOT ONE policy defined on it, reachable only through three new
--      SECURITY DEFINER functions (atd_check_login_allowed,
--      atd_record_login_attempt, atd_count_active_lockouts) that run with
--      the function owner's privileges regardless of caller — the same
--      trust boundary atd_role() already relies on. atendify.html now calls
--      these instead of reading/writing the old kv_store prefix directly.
--      Any rows already sitting under the old 'loginAttempts:' kv_store
--      prefix are harmless leftovers (lockouts are short-lived by design)
--      and are left in place rather than migrated.
--  13. Fixes two compounding bugs that, together, meant NO JCF officer —
--      for any division, real or demo — could ever see any of their own
--      division's Noise Abatement filings, attached documents, or watch
--      list entries, despite being able to log in and see their own roster
--      just fine:
--        a. atd_jcf_jurisdiction_muni_id() looked up a plain
--           'jcfBranch:{branchId}' record for `linkedMuniId` — but the app
--           never writes that record (only jcfBranch:{id}:signature and
--           jcfBranch:{id}:rolePermissions); `linkedMuniId` actually lives
--           on the division's own agency:{id} record. This function has
--           returned null for every division since the original schema
--           handoff, silently breaking every policy that depends on it —
--           including the pre-existing "jcfd read applications/venues in
--           their jurisdiction" policies, not just the ones below.
--        b. Separately, jcfApplication/jcfApplicationFiles/jcfWatchlist
--           were scoped by the SAME key_part2-based policy as
--           jcfBranch/jcfdUser ("jcfd manage their own branch's records")
--           — but key_part2 is the appNumber or TRN for those three
--           prefixes, never the branch id, so that check could never match
--           regardless of (a). Split into their own policies, scoped by
--           value (jcfApplication.muniId, jcfWatchlist.agencyId) or, for
--           jcfApplicationFiles (which carries neither), by looking up its
--           sibling jcfApplication:{appNumber} row via two new helper
--           functions.
--      Confirmed locally, before this fix: a correctly-provisioned jcfd
--      Chief profile for a real division's branch id got 0 rows back
--      querying either a jcfApplication belonging to their own
--      jurisdiction, or atd_jcf_jurisdiction_muni_id() directly. After the
--      fix, the same profile reads and updates it correctly, a different
--      division's Chief still gets 0 rows, and the applicant who owns the
--      filing still reads their own jcfApplicationFiles record.
--
-- If you have NOT run supabase_schema.sql yet, ignore this file — the
-- current supabase_schema.sql already has all these fixes built in; just run
-- that one file instead.
-- ============================================================================

alter table public.kv_store drop constraint if exists kv_store_updated_by_fkey;
alter table public.kv_store add constraint kv_store_updated_by_fkey
  foreign key (updated_by) references auth.users(id) on delete set null;

insert into public.staff_invites (email, role, display_name)
values ('admin@gmail.com', 'admin', 'Platform Administrator')
on conflict (email) do nothing;

-- ---- Fix #4: the actual bug behind every stuck login ----------------------
create or replace function public.atd_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inv record;
begin
  select * into inv from public.staff_invites where lower(email) = lower(new.email);
  if inv.email is not null then
    insert into public.profiles (id, role, agency_id, jcf_branch_id, permissions, display_name, email)
    values (new.id, inv.role, inv.agency_id, inv.jcf_branch_id, inv.permissions, inv.display_name, new.email);
  else
    insert into public.profiles (id, role, display_name, email)
    values (new.id, 'poa', new.email, new.email);
  end if;
  return new;
end;
$$;

-- ---- Fix #5: pre-authorize every seeded muni/JCF officer ------------------
insert into public.staff_invites (email, role, agency_id, display_name) values
  ('andrea.powell@kmc.gov.jm', 'muni', '1', 'Andrea Powell'),
  ('paul.bennett@kmc.gov.jm', 'muni', '1', 'Paul Bennett'),
  ('sasha.grant@kmc.gov.jm', 'muni', '1', 'Sasha Grant'),
  ('marlon.reid@stmary.gov.jm', 'muni', '4', 'Marlon Reid'),
  ('tanya.ford@stmary.gov.jm', 'muni', '4', 'Tanya Ford'),
  ('richard.dunn@stmary.gov.jm', 'muni', '4', 'Richard Dunn'),
  ('kerryann.blake@mobay.gov.jm', 'muni', '7', 'Kerry-Ann Blake'),
  ('odain.clarke@mobay.gov.jm', 'muni', '7', 'Odain Clarke'),
  ('michelle.barrett@mobay.gov.jm', 'muni', '7', 'Michelle Barrett'),
  ('devon.hylton@manchester.gov.jm', 'muni', '11', 'Devon Hylton'),
  ('sherika.palmer@manchester.gov.jm', 'muni', '11', 'Sherika Palmer'),
  ('andre.lawson@manchester.gov.jm', 'muni', '11', 'Andre Lawson'),
  ('portmore.admin@gov.jm', 'muni', '14', 'Sasha-Kay Reid')
on conflict (email) do update set role = excluded.role, agency_id = excluded.agency_id, display_name = excluded.display_name;

insert into public.staff_invites (email, role, jcf_branch_id, display_name) values
  ('rohan.blake@jcf.gov.jm', 'jcfd', '5', 'Insp. Rohan Blake'),
  ('michelle.grant@jcf.gov.jm', 'jcfd', '5', 'Sgt. Michelle Grant'),
  ('andre.douglas@jcf.gov.jm', 'jcfd', '5', 'Const. Andre Douglas'),
  ('hwt.station@jcf.gov.jm', 'jcfd', '5', 'Half Way Tree Station'),
  ('paula.grant@jcf.gov.jm', 'jcfd', '7', 'Insp. Paula Grant'),
  ('kemar.wilson@jcf.gov.jm', 'jcfd', '7', 'Sgt. Kemar Wilson'),
  ('portmaria.station@jcf.gov.jm', 'jcfd', '7', 'Port Maria Station')
on conflict (email) do update set role = excluded.role, jcf_branch_id = excluded.jcf_branch_id, display_name = excluded.display_name;

-- ---- Fix #6: repair any account already stuck as 'poa' by bug #4 ---------
update public.profiles p
set role = si.role,
    agency_id = si.agency_id,
    jcf_branch_id = si.jcf_branch_id,
    permissions = si.permissions,
    display_name = coalesce(p.display_name, si.display_name)
from public.staff_invites si
where lower(p.email) = lower(si.email)
  and p.role = 'poa';

drop policy if exists "kv_store: poa reads/writes own applications" on public.kv_store;
create policy "kv_store: poa reads/writes own applications"
  on public.kv_store for select
  using (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

drop policy if exists "kv_store: poa inserts own applications" on public.kv_store;
create policy "kv_store: poa inserts own applications"
  on public.kv_store for insert
  with check (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

drop policy if exists "kv_store: poa reads/writes own jcf filings" on public.kv_store;
create policy "kv_store: poa reads/writes own jcf filings"
  on public.kv_store for select
  using (
    prefix in ('jcfApplication','jcfApplicationFiles')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

drop policy if exists "kv_store: poa inserts own jcf filings" on public.kv_store;
create policy "kv_store: poa inserts own jcf filings"
  on public.kv_store for insert
  with check (
    prefix in ('jcfApplication','jcfApplicationFiles')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

-- ---- Fix #7: let anyone read the 4 one-time-seed completion flags --------
drop policy if exists "kv_store: seed-completion flags are publicly readable" on public.kv_store;
create policy "kv_store: seed-completion flags are publicly readable"
  on public.kv_store for select
  using (key in ('platform:agenciesSeeded','platform:muniUsersSeeded','platform:demoDataSeeded','platform:rolesSeeded'));

-- ---- Fix #8: add jcfdUser to the JCF-scoped records policy ---------------
drop policy if exists "kv_store: jcfd manage their own branch's records" on public.kv_store;
create policy "kv_store: jcfd manage their own branch's records"
  on public.kv_store for all
  using (
    prefix in ('jcfApplication','jcfApplicationFiles','jcfWatchlist','jcfBranch','jcfdUser')
    and public.atd_role() = 'jcfd'
    and key_part2 = public.atd_jcf_branch_id()
  )
  with check (
    prefix in ('jcfApplication','jcfApplicationFiles','jcfWatchlist','jcfBranch','jcfdUser')
    and public.atd_role() = 'jcfd'
    and key_part2 = public.atd_jcf_branch_id()
  );

-- ---- Fix #9: let a failed login attempt actually reach the audit log ----
drop policy if exists "kv_store: authenticated append to audit log" on public.kv_store;
create policy "kv_store: authenticated append to audit log" on public.kv_store
  for insert with check (
    prefix = 'auditLog'
    and (auth.uid() is not null or (value->>'action') = 'login.failed')
  );

-- ---- Fix #10: add the 5th seed-completion flag to fix #7's policy --------
drop policy if exists "kv_store: seed-completion flags are publicly readable" on public.kv_store;
create policy "kv_store: seed-completion flags are publicly readable"
  on public.kv_store for select
  using (key in ('platform:agenciesSeeded','platform:muniUsersSeeded','platform:demoDataSeeded','platform:rolesSeeded','platform:jcfdUsersSeeded'));

-- ---- Fix #11: let poa actually re-save their own applications/filings ----
drop policy if exists "kv_store: poa updates own applications" on public.kv_store;
create policy "kv_store: poa updates own applications"
  on public.kv_store for update
  using (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  )
  with check (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

drop policy if exists "kv_store: poa updates own jcf filings" on public.kv_store;
create policy "kv_store: poa updates own jcf filings"
  on public.kv_store for update
  using (
    prefix in ('jcfApplication','jcfApplicationFiles')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  )
  with check (
    prefix in ('jcfApplication','jcfApplicationFiles')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

-- ---- Fix #12: login lockout, enforced server-side -------------------------
drop policy if exists "kv_store: anyone can read/write login attempt counters" on public.kv_store;

create table if not exists public.login_attempts (
  portal        text not null,
  email         text not null,
  attempt_count int not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now(),
  primary key (portal, email)
);
alter table public.login_attempts enable row level security;
-- Deliberately no policies here — see the fix #12 note above.

create or replace function public.atd_check_login_allowed(p_portal text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(p_email, ''));
  v_row public.login_attempts%rowtype;
  v_mins_left int;
begin
  if v_email = '' then
    return jsonb_build_object('allowed', true);
  end if;

  select * into v_row from public.login_attempts where portal = p_portal and email = v_email;
  if not found or v_row.locked_until is null or v_row.locked_until <= now() then
    return jsonb_build_object('allowed', true);
  end if;

  v_mins_left := greatest(1, ceil(extract(epoch from (v_row.locked_until - now())) / 60));
  return jsonb_build_object(
    'allowed', false,
    'message', format('Too many failed attempts. Try again in %s minute(s).', v_mins_left)
  );
end;
$$;

create or replace function public.atd_record_login_attempt(p_portal text, p_email text, p_success boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(p_email, ''));
  v_policy jsonb;
  v_max int := 5;
  v_lockout_minutes int := 15;
  v_row public.login_attempts%rowtype;
begin
  if v_email = '' then
    return;
  end if;

  if p_success then
    delete from public.login_attempts where portal = p_portal and email = v_email;
    return;
  end if;

  select value into v_policy from public.kv_store where key = 'platform:securityPolicy';
  if v_policy is not null then
    v_max := coalesce((v_policy->>'maxFailedAttempts')::int, v_max);
    v_lockout_minutes := coalesce((v_policy->>'lockoutMinutes')::int, v_lockout_minutes);
  end if;

  insert into public.login_attempts as la (portal, email, attempt_count, locked_until, updated_at)
  values (p_portal, v_email, 1, null, now())
  on conflict (portal, email) do update
    set attempt_count = la.attempt_count + 1,
        updated_at = now()
  returning * into v_row;

  if v_row.attempt_count >= v_max then
    update public.login_attempts
    set locked_until = now() + make_interval(mins => v_lockout_minutes),
        attempt_count = 0
    where portal = p_portal and email = v_email;
  end if;
end;
$$;

create or replace function public.atd_count_active_lockouts()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  -- coalesce matters here: atd_role() returns NULL for a caller with no
  -- profile row at all, and "NULL <> 'admin'" evaluates to NULL, not TRUE —
  -- an `if NULL then` silently falls through in PL/pgSQL instead of
  -- short-circuiting, which would let exactly the least-trusted caller
  -- reach the count query below. Caught by testing this as anon locally.
  if coalesce(public.atd_role(), '') <> 'admin' then
    return 0;
  end if;
  select count(*) into v_count from public.login_attempts
  where locked_until is not null and locked_until > now();
  return v_count;
end;
$$;

-- ---- Fix #13: JCF officers could not see their own division's filings ----
-- See the fix #13 note in the header above for the full story. Part (a):
-- the jurisdiction lookup itself was querying the wrong record.
create or replace function public.atd_jcf_jurisdiction_muni_id() returns text
language sql stable security definer set search_path = public as $$
  select value->>'muniNumber'
  from public.kv_store
  where key = 'agency:' || (
    select value->>'linkedMuniId'
    from public.kv_store
    where key = 'agency:' || public.atd_jcf_branch_id()
  );
$$;

-- Part (b): jcfApplication/jcfApplicationFiles need their own policies,
-- separate from jcfBranch/jcfdUser's key_part2-based one.
create or replace function public.atd_jcf_application_muni_id(app_number text) returns text
language sql stable security definer set search_path = public as $$
  select value->>'muniId' from public.kv_store where key = 'jcfApplication:' || app_number;
$$;

create or replace function public.atd_jcf_application_owner_email(app_number text) returns text
language sql stable security definer set search_path = public as $$
  select value->>'ownerEmail' from public.kv_store where key = 'jcfApplication:' || app_number;
$$;

drop policy if exists "kv_store: jcfd manage their own branch's records" on public.kv_store;
create policy "kv_store: jcfd manage their own branch's records"
  on public.kv_store for all
  using (
    prefix in ('jcfBranch','jcfdUser')
    and public.atd_role() = 'jcfd'
    and key_part2 = public.atd_jcf_branch_id()
  )
  with check (
    prefix in ('jcfBranch','jcfdUser')
    and public.atd_role() = 'jcfd'
    and key_part2 = public.atd_jcf_branch_id()
  );

drop policy if exists "kv_store: jcfd read jcf filings in their jurisdiction" on public.kv_store;
create policy "kv_store: jcfd read jcf filings in their jurisdiction"
  on public.kv_store for select
  using (
    prefix = 'jcfApplication'
    and public.atd_role() = 'jcfd'
    and (value->>'muniId') = public.atd_jcf_jurisdiction_muni_id()
  );
drop policy if exists "kv_store: jcfd update jcf filings in their jurisdiction" on public.kv_store;
create policy "kv_store: jcfd update jcf filings in their jurisdiction"
  on public.kv_store for update
  using (
    prefix = 'jcfApplication'
    and public.atd_role() = 'jcfd'
    and (value->>'muniId') = public.atd_jcf_jurisdiction_muni_id()
  )
  with check (
    prefix = 'jcfApplication'
    and public.atd_role() = 'jcfd'
    and (value->>'muniId') = public.atd_jcf_jurisdiction_muni_id()
  );

drop policy if exists "kv_store: poa reads/writes own jcf filings" on public.kv_store;
create policy "kv_store: poa reads/writes own jcf filings"
  on public.kv_store for select
  using (
    prefix = 'jcfApplication'
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );
drop policy if exists "kv_store: poa inserts own jcf filings" on public.kv_store;
create policy "kv_store: poa inserts own jcf filings"
  on public.kv_store for insert
  with check (
    prefix = 'jcfApplication'
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );
drop policy if exists "kv_store: poa updates own jcf filings" on public.kv_store;
create policy "kv_store: poa updates own jcf filings"
  on public.kv_store for update
  using (
    prefix = 'jcfApplication'
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  )
  with check (
    prefix = 'jcfApplication'
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );

drop policy if exists "kv_store: poa read own jcf filing files" on public.kv_store;
create policy "kv_store: poa read own jcf filing files"
  on public.kv_store for select
  using (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'poa'
    and public.atd_jcf_application_owner_email(key_part2) = auth.email()
  );
drop policy if exists "kv_store: poa insert own jcf filing files" on public.kv_store;
create policy "kv_store: poa insert own jcf filing files"
  on public.kv_store for insert
  with check (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'poa'
    and public.atd_jcf_application_owner_email(key_part2) = auth.email()
  );
drop policy if exists "kv_store: poa update own jcf filing files" on public.kv_store;
create policy "kv_store: poa update own jcf filing files"
  on public.kv_store for update
  using (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'poa'
    and public.atd_jcf_application_owner_email(key_part2) = auth.email()
  )
  with check (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'poa'
    and public.atd_jcf_application_owner_email(key_part2) = auth.email()
  );
drop policy if exists "kv_store: jcfd read jcf filing files in their jurisdiction" on public.kv_store;
create policy "kv_store: jcfd read jcf filing files in their jurisdiction"
  on public.kv_store for select
  using (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'jcfd'
    and public.atd_jcf_application_muni_id(key_part2) = public.atd_jcf_jurisdiction_muni_id()
  );

drop policy if exists "kv_store: jcfd manage their own division's watchlist entries" on public.kv_store;
create policy "kv_store: jcfd manage their own division's watchlist entries"
  on public.kv_store for all
  using (
    prefix = 'jcfWatchlist'
    and public.atd_role() = 'jcfd'
    and (value->>'agencyId') = public.atd_jcf_branch_id()
  )
  with check (
    prefix = 'jcfWatchlist'
    and public.atd_role() = 'jcfd'
    and (value->>'agencyId') = public.atd_jcf_branch_id()
  );
