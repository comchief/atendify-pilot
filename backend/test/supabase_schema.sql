-- ============================================================================
-- Atendify — Phase 1 backend schema (Supabase / Postgres)
-- ============================================================================
-- What this is: a "lift and shift" schema, not a full re-normalization.
--
-- Today, every portal in atendify.html talks to a single shim, window.storage,
-- with exactly four operations: get(key), set(key, jsonString), delete(key),
-- list(prefix) — a generic key/value store, currently backed by
-- window.localStorage (private to one browser, never shared).
--
-- This schema gives that exact same shape a real home: one shared table,
-- reachable from every device, with Postgres row-level security (RLS)
-- standing in for "which portal/agency is allowed to touch which records."
-- Pairing it with atd_supabase_adapter.js (same folder) means the ~1,000+
-- call sites already written against window.storage.get/set/delete/list do
-- not need to change — only the shim's *implementation* changes.
--
-- A fully normalized schema (separate typed tables per entity, real foreign
-- keys) is real future value, but it would touch a very large share of a
-- 20,000-line file that currently has zero automated regression tests. For a
-- small, time-boxed pilot (one Municipal Corporation, one JCF division),
-- shipping the shared-backend fix first — and re-normalizing once real
-- pilot usage patterns are known — is the safer order of operations.
--
-- Run this whole file once, in the Supabase SQL editor, on a fresh project.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Profiles — one row per authenticated person, linking Supabase Auth to
--    the app's existing role/permission model (admin / muni / jcfd / poa).
-- ----------------------------------------------------------------------------

create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  role              text not null check (role in ('admin','muni','jcfd','poa')),
  agency_id         text,        -- muniNumber, for role = 'muni'
  jcf_branch_id     text,        -- jcfBranch id, for role = 'jcfd'
  permissions       jsonb not null default '{}'::jsonb,
  display_name      text,
  email             text,
  created_at        timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Admins invite staff by pre-registering their email + intended role here.
-- When that person signs up in Supabase Auth, a trigger below copies the
-- invite into their profile automatically. This replaces the old model of
-- "admin hardcodes a seeded user object with a plaintext password."
create table if not exists public.staff_invites (
  email             text primary key,
  role              text not null check (role in ('admin','muni','jcfd')),
  agency_id         text,
  jcf_branch_id     text,
  permissions       jsonb not null default '{}'::jsonb,
  display_name      text,
  created_at        timestamptz not null default now()
);

alter table public.staff_invites enable row level security;

-- Pre-authorizes the platform's one Admin account so its first real signup
-- (via the "Create the admin account" link on the Admin login screen) is
-- assigned role = 'admin' instead of landing as a public applicant. Change
-- this email first if the real admin won't sign up as admin@gmail.com.
insert into public.staff_invites (email, role, display_name)
values ('admin@gmail.com', 'admin', 'Platform Administrator')
on conflict (email) do nothing;

-- Same pre-authorization for every Municipal/JCF officer already seeded in
-- the app's demo/pilot data (ATD_MUNI_USER_SEED and jcfdStaffUsers in
-- atendify.html), so each of them can also click "create your password" and
-- land in the right role instead of as a public applicant.
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
  -- Checking "inv is not null" on the whole record is wrong here: Postgres
  -- only considers a composite/record value NOT NULL when EVERY field in it
  -- is non-null. Every real staff_invites row has at least one null column
  -- by design (a muni invite has jcf_branch_id null; a jcfd invite has
  -- agency_id null; the admin invite has both null) — so "inv is not null"
  -- was false for every invite that ever existed, silently sending every
  -- pre-authorized signup down the "no invite" branch below instead. Check
  -- a single not-null column (email, the table's primary key) instead: it's
  -- only set if a row was actually found.
  if inv.email is not null then
    insert into public.profiles (id, role, agency_id, jcf_branch_id, permissions, display_name, email)
    values (new.id, inv.role, inv.agency_id, inv.jcf_branch_id, inv.permissions, inv.display_name, new.email);
  else
    -- No staff invite on file: treat as a public applicant (POA) account.
    insert into public.profiles (id, role, display_name, email)
    values (new.id, 'poa', new.email, new.email);
  end if;
  return new;
end;
$$;

drop trigger if exists atd_on_auth_user_created on auth.users;
create trigger atd_on_auth_user_created
  after insert on auth.users
  for each row execute function public.atd_handle_new_user();

-- Helper functions used inside RLS policies below (security definer so they
-- can read `profiles` even though profiles' own RLS restricts direct access).
create or replace function public.atd_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.atd_agency_id() returns text
language sql stable security definer set search_path = public as $$
  select agency_id from public.profiles where id = auth.uid();
$$;

create or replace function public.atd_jcf_branch_id() returns text
language sql stable security definer set search_path = public as $$
  select jcf_branch_id from public.profiles where id = auth.uid();
$$;

-- Note: atd_jcf_jurisdiction_muni_id() is defined further down, right after
-- the kv_store table it queries is created — a `language sql` function's
-- body is validated against real tables at CREATE FUNCTION time, so it
-- can't be defined before the table it reads from exists.

create policy "profiles: read own" on public.profiles
  for select using (id = auth.uid());
create policy "profiles: admin reads all" on public.profiles
  for select using (public.atd_role() = 'admin');
create policy "staff_invites: admin only" on public.staff_invites
  for all using (public.atd_role() = 'admin') with check (public.atd_role() = 'admin');

-- ----------------------------------------------------------------------------
-- 2. kv_store — the shared replacement for window.localStorage.
-- ----------------------------------------------------------------------------

create table if not exists public.kv_store (
  key         text primary key,
  value       jsonb not null,
  prefix      text generated always as (split_part(key, ':', 1)) stored,
  key_part2   text generated always as (split_part(key, ':', 2)) stored,
  updated_at  timestamptz not null default now(),
  -- on delete set null (not cascade, and not left unset): if a user account
  -- is ever removed, every record they touched should keep existing — this
  -- is an audit trail column ("who last touched this row"), not ownership.
  -- Leaving this FK with no delete action (the default) blocks deleting ANY
  -- user who has ever written a single row, with Postgres's generic
  -- "violates foreign key constraint" error surfacing in Supabase as
  -- "Database error deleting user" — including for a brand new admin/staff
  -- account you're just trying to clean up and retry.
  updated_by  uuid references auth.users(id) on delete set null
);

create index if not exists kv_store_prefix_idx on public.kv_store (prefix);
create index if not exists kv_store_key_part2_idx on public.kv_store (prefix, key_part2);
create index if not exists kv_store_muni_id_idx on public.kv_store (((value->>'muniId')));

-- A JCF division's jurisdiction is the muniId of the Municipal Corporation
-- its own agency record is linked to (mirrors jcfd_jurisdictionMuniId() in
-- the app, which reads jcfdCurrentBranch.linkedMuniId — jcfdCurrentBranch
-- IS that division's own agency record, loaded via jcfd_agencies().find(a
-- => a.id === ...), the same agency:{id} row ATD_AGENCY_SEED / the admin
-- portal's agency editor already write `linkedMuniId` onto).
--
-- This function originally looked up 'jcfBranch:' || branch_id instead of
-- 'agency:' || branch_id — but the app never writes a plain jcfBranch:{id}
-- record (only jcfBranch:{id}:signature and jcfBranch:{id}:rolePermissions,
-- neither of which carries linkedMuniId), so that lookup always resolved to
-- nothing and this function always returned null for every division, real
-- or demo, since the very first version of this schema. Every policy that
-- depends on it — "jcfd read applications in their jurisdiction", "jcfd
-- read venues/promotions in their jurisdiction", and (as of this same fix
-- round) the corrected jcfApplication/jcfApplicationFiles policies below —
-- was silently returning zero rows for every JCF officer as a result.
-- Confirmed locally: querying this function directly as a correctly
-- provisioned branch-7 jcfd profile returned null before this fix.
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

-- jcfApplication:{appNumber} / jcfApplicationFiles:{appNumber} — unlike
-- jcfBranch:{id} and jcfdUser:{branchId}:{id}, the branch/division is NOT
-- part of these keys (key_part2 is the appNumber, not a branch id), so they
-- can't be scoped by key_part2 the way Family 5's policy below originally
-- assumed for all five JCF-scoped prefixes at once. jcfApplication itself
-- carries a `muniId` in its JSON value (the linked POA application's
-- municipality) that can be checked directly; jcfApplicationFiles carries
-- neither that nor an ownerEmail, only raw file data, so its own policies
-- have to look up its sibling jcfApplication:{appNumber} row instead —
-- these two helpers do that lookup, security definer so the check works
-- regardless of whether the caller could otherwise read that sibling row.
create or replace function public.atd_jcf_application_muni_id(app_number text) returns text
language sql stable security definer set search_path = public as $$
  select value->>'muniId' from public.kv_store where key = 'jcfApplication:' || app_number;
$$;

create or replace function public.atd_jcf_application_owner_email(app_number text) returns text
language sql stable security definer set search_path = public as $$
  select value->>'ownerEmail' from public.kv_store where key = 'jcfApplication:' || app_number;
$$;

alter table public.kv_store enable row level security;

create or replace function public.atd_touch_kv_store()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists atd_kv_store_touch on public.kv_store;
create trigger atd_kv_store_touch
  before insert or update on public.kv_store
  for each row execute function public.atd_touch_kv_store();

-- Default posture: deny everything, then open up by prefix family below.
-- Admin bypasses every rule.
create policy "kv_store: admin full access" on public.kv_store
  for all using (public.atd_role() = 'admin') with check (public.atd_role() = 'admin');

-- --- Family 1: public directory (agency:*) --------------------------------
-- The POA parish/municipality dropdown has to work before anyone logs in,
-- so this is the one prefix readable anonymously. Only admin can write it —
-- Admin already owns Municipal Corporation onboarding today.
create policy "kv_store: agency directory is publicly readable" on public.kv_store
  for select using (prefix = 'agency');

-- The app's own one-time client-side seed bootstraps (agency directory,
-- municipal officer roster, demo venues/ads/watchlist, role templates, JCF
-- officer roster) each check one of these five flags before attempting to
-- write their data, so they only ever run once. Under RLS those flags live
-- in the admin-only 'platform' prefix (see "no separate policy needed"
-- below) — which means an anonymous visitor, or anyone signed in as
-- something other than admin, can never even READ the flag, so the check
-- always comes back empty and the app retries the (doomed, RLS-blocked)
-- write on every single page load, forever. This is harmless in effect —
-- the write fails and the app falls back to its local seed data — but it's
-- noisy. These five keys are just boolean/timestamp completion markers with
-- nothing sensitive in them (unlike platform:securityPolicy or
-- platform:integrationsConfig, which stay admin-only), so making just these
-- five readable by anyone lets the check actually succeed once the real
-- data has been loaded via reference_data_seed.sql, and the app stops
-- trying forever.
create policy "kv_store: seed-completion flags are publicly readable" on public.kv_store
  for select using (key in ('platform:agenciesSeeded','platform:muniUsersSeeded','platform:demoDataSeeded','platform:rolesSeeded','platform:jcfdUsersSeeded'));

-- --- Family 2: agency-scoped, muniId inside the JSON value ----------------
-- venue / adItem / promotion / promoRedemption / notification / muniUser
-- all carry a muniId (or resolvable owner agency) field in their value.
create policy "kv_store: muni staff read own agency records (value.muniId)"
  on public.kv_store for select
  using (
    prefix in ('venue','adItem','promotion','promoRedemption','notification','muniUser')
    and public.atd_role() = 'muni'
    and (value->>'muniId') = public.atd_agency_id()
  );
create policy "kv_store: muni staff write own agency records (value.muniId)"
  on public.kv_store for insert
  with check (
    prefix in ('venue','adItem','promotion','promoRedemption','notification','muniUser')
    and public.atd_role() = 'muni'
    and (value->>'muniId') = public.atd_agency_id()
  );
create policy "kv_store: muni staff update own agency records (value.muniId)"
  on public.kv_store for update
  using (
    prefix in ('venue','adItem','promotion','promoRedemption','notification','muniUser')
    and public.atd_role() = 'muni'
    and (value->>'muniId') = public.atd_agency_id()
  );

-- JCF staff need read-only visibility into the venues/promoters in their own
-- jurisdiction (e.g. the shared Events Calendar, venue violation lookups).
create policy "kv_store: jcfd read venues/promotions in their jurisdiction"
  on public.kv_store for select
  using (
    prefix in ('venue','promotion')
    and public.atd_role() = 'jcfd'
    and (value->>'muniId') = public.atd_jcf_jurisdiction_muni_id()
  );

-- --- Family 3: agency-scoped, muniId embedded in the key itself -----------
-- municipality:{muniId}:bankInfo / :settings / :signature, archiveYear:{muniId}:{year},
-- formElements:{muniId}
create policy "kv_store: muni staff read own agency records (key muniId)"
  on public.kv_store for select
  using (
    prefix in ('municipality','archiveYear','formElements')
    and public.atd_role() = 'muni'
    and key_part2 = public.atd_agency_id()
  );
create policy "kv_store: muni staff write own agency records (key muniId)"
  on public.kv_store for insert
  with check (
    prefix in ('municipality','archiveYear','formElements')
    and public.atd_role() = 'muni'
    and key_part2 = public.atd_agency_id()
  );
create policy "kv_store: muni staff update own agency records (key muniId)"
  on public.kv_store for update
  using (
    prefix in ('municipality','archiveYear','formElements')
    and public.atd_role() = 'muni'
    and key_part2 = public.atd_agency_id()
  );

-- --- Family 4: application lifecycle (POA-authored, muni-reviewed) --------
-- The applicant who owns an application can read/update their own record;
-- the Municipal Corporation named on it can read/update it once filed;
-- their JCF counterpart gets read-only visibility for the same reasons
-- as Family 2 above. File-pointer rows (applicationPhotoId etc.) follow the
-- same rule as the parent application record.
create policy "kv_store: poa reads/writes own applications"
  on public.kv_store for select
  using (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );
create policy "kv_store: poa inserts own applications"
  on public.kv_store for insert
  with check (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );
-- Every write in this app goes through window.storage.set(), which always
-- issues an upsert (INSERT ... ON CONFLICT DO UPDATE) — Postgres requires
-- an applicable UPDATE policy to actually perform the DO UPDATE branch
-- whenever a real conflict occurs, not just an INSERT policy. Without this,
-- an applicant's very FIRST save of a new application key succeeded (no
-- conflict yet), but every subsequent re-save of that SAME key — paying a
-- fee, uploading a document, any later wizard step — hit "new row violates
-- row-level security policy" the moment it genuinely conflicted, because
-- there was no UPDATE policy letting the DO UPDATE through. Confirmed by
-- reproducing the exact failure locally: a non-conflicting upsert succeeds
-- with only insert+select, but a genuinely conflicting one fails until an
-- update policy exists too.
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
create policy "kv_store: muni staff read/update applications filed with them"
  on public.kv_store for select
  using (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'muni'
    and (value->>'muniId') = public.atd_agency_id()
  );
create policy "kv_store: muni staff update applications filed with them"
  on public.kv_store for update
  using (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'muni'
    and (value->>'muniId') = public.atd_agency_id()
  );
create policy "kv_store: jcfd read applications in their jurisdiction"
  on public.kv_store for select
  using (
    prefix in ('application','applicationPhotoId','applicationFlier','applicationLogo',
               'applicationOwnership','applicationFeeReceipt','applicationPaymentReceipt',
               'applicationAdditionalPaymentReceipt')
    and public.atd_role() = 'jcfd'
    and (value->>'muniId') = public.atd_jcf_jurisdiction_muni_id()
  );

-- --- Family 5: JCF-scoped records ------------------------------------------
-- jcfdUser:{branchId}:{id} — a division's own officer roster, the JCF
-- equivalent of Family 2's muniUser records. Keyed (not value-scoped) the
-- same way jcfBranch:{id}:signature already is.
--
-- jcfApplication/jcfApplicationFiles/jcfWatchlist used to be lumped into
-- this same key_part2-based policy, but key_part2 is the appNumber (for the
-- first two) or the TRN (for jcfWatchlist) — never the branch id — so that
-- check could never actually match for any of the three, for any division,
-- real or demo. A real jcfd Chief/officer could sign in, but every read of
-- their own division's filings and watch-list entries came back empty, and
-- every attempt to review/decide one failed RLS. Confirmed locally: a
-- correctly-provisioned jcfd profile for branch 7, querying
-- jcfApplication:* for a filing that genuinely belongs to branch 7's
-- jurisdiction, got 0 rows back before this fix. Split into its own,
-- correctly-scoped policies below instead.
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

-- jcfApplication carries `muniId` (the linked POA application's
-- municipality) in its own JSON value, so — unlike jcfApplicationFiles
-- below — it can be scoped directly, the same way Family 4's own
-- "jcfd read applications in their jurisdiction" policy already scopes the
-- POA-side `application` record.
create policy "kv_store: jcfd read jcf filings in their jurisdiction"
  on public.kv_store for select
  using (
    prefix = 'jcfApplication'
    and public.atd_role() = 'jcfd'
    and (value->>'muniId') = public.atd_jcf_jurisdiction_muni_id()
  );
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

create policy "kv_store: poa reads/writes own jcf filings"
  on public.kv_store for select
  using (
    prefix = 'jcfApplication'
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );
create policy "kv_store: poa inserts own jcf filings"
  on public.kv_store for insert
  with check (
    prefix = 'jcfApplication'
    and public.atd_role() = 'poa'
    and (value->>'ownerEmail') = auth.email()
  );
-- Same missing-UPDATE-policy gap as "poa updates own applications" above —
-- an applicant's JCF Noise Abatement filing could be created but never
-- re-saved afterward without this.
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

-- jcfApplicationFiles:{appNumber} carries neither ownerEmail nor muniId —
-- only raw file data (see the record atendify.html actually writes) — so
-- its access has to be decided by looking at its sibling
-- jcfApplication:{appNumber} row (same appNumber, via key_part2) instead of
-- anything on the row itself. Both directions were previously broken: poa's
-- own upload (best-effort, silently swallowed on failure) had nothing to
-- check an ownerEmail against, and jcfd's document viewer
-- (jcfd_openDocModal) had nothing to check a muniId against either.
create policy "kv_store: poa read own jcf filing files"
  on public.kv_store for select
  using (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'poa'
    and public.atd_jcf_application_owner_email(key_part2) = auth.email()
  );
create policy "kv_store: poa insert own jcf filing files"
  on public.kv_store for insert
  with check (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'poa'
    and public.atd_jcf_application_owner_email(key_part2) = auth.email()
  );
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
create policy "kv_store: jcfd read jcf filing files in their jurisdiction"
  on public.kv_store for select
  using (
    prefix = 'jcfApplicationFiles'
    and public.atd_role() = 'jcfd'
    and public.atd_jcf_application_muni_id(key_part2) = public.atd_jcf_jurisdiction_muni_id()
  );

-- jcfWatchlist:{trn} carries `agencyId` — the JCF division's own id, i.e.
-- exactly what atd_jcf_branch_id() returns — so unlike jcfApplication this
-- one scopes directly off its own value, just not off key_part2 (which is
-- the TRN here, not the agency id).
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

-- --- Family 6: shared cross-agency watchlist (TRN blacklist) ---------------
-- Any signed-in staff member (muni or jcfd) can read it; only muni/admin add
-- to it, mirroring who can flag a promoter today.
create policy "kv_store: staff read shared watchlist" on public.kv_store
  for select using (prefix = 'watchlist' and public.atd_role() in ('muni','jcfd'));
create policy "kv_store: muni staff write shared watchlist" on public.kv_store
  for insert with check (prefix = 'watchlist' and public.atd_role() = 'muni');
create policy "kv_store: muni staff update shared watchlist" on public.kv_store
  for update using (prefix = 'watchlist' and public.atd_role() = 'muni');

-- --- Family 7: a person's own account/login-adjacent records ---------------
create policy "kv_store: read own account record" on public.kv_store
  for select using (prefix in ('accountUser','accountDraft') and key_part2 = auth.email());
create policy "kv_store: write own account record" on public.kv_store
  for insert with check (prefix in ('accountUser','accountDraft') and key_part2 = auth.email());
create policy "kv_store: update own account record" on public.kv_store
  for update using (prefix in ('accountUser','accountDraft') and key_part2 = auth.email());

-- --- Family 8: login lockout, enforced server-side ------------------------
-- This used to be a kv_store prefix ('loginAttempts') left open to anon
-- read/write "by design," on the reasoning that it only holds attempt
-- counts, not credentials. That reasoning missed the actual risk: with
-- direct read/write access to its own counter, any client can reset its own
-- lockout at will, or fabricate one for someone else, by calling the
-- Supabase REST API directly instead of going through this app's own JS —
-- the enforcement lived entirely in code the client fully controls. A
-- lockout policy that can be turned off by the person it's meant to slow
-- down isn't a real lockout.
--
-- Fixed by moving both the storage AND the enforcement logic server-side:
-- a dedicated table with row level security enabled and NOT ONE policy
-- defined on it (so ordinary reads/writes are refused outright, the same
-- "deny by default" RLS gives every other table here), reachable only
-- through the three SECURITY DEFINER functions below. Those run with the
-- function owner's privileges regardless of who calls them — the same
-- trust boundary atd_role() already relies on to read profiles despite
-- profiles' own RLS restricting direct access — so a client can check or
-- record an attempt, but can never read, rewrite, or clear the counter
-- directly.
create table if not exists public.login_attempts (
  portal        text not null,
  email         text not null,
  attempt_count int not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now(),
  primary key (portal, email)
);
alter table public.login_attempts enable row level security;
-- Deliberately no policies here — see the comment above.

-- Returns { allowed, message } for the given portal+email, reading nothing
-- the client couldn't already infer from a login attempt itself failing.
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

-- Records one login attempt. A success clears the counter outright; a
-- failure increments it and, on crossing the configured threshold, sets
-- locked_until and resets the count — all in one atomic upsert, so two
-- failed attempts arriving at nearly the same moment can't both land under
-- the threshold and neither triggers the lockout. Reads the same
-- platform:securityPolicy record the Admin "Security" screen already
-- writes, so the two stay in sync without a second copy of the policy.
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

-- Backs the Admin dashboard's "accounts currently locked out" count.
-- Restricted to admin so this isn't a side channel for enumerating which
-- emails are mid-lockout.
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
  -- profile row at all (e.g. a truly anonymous request), and
  -- "NULL <> 'admin'" evaluates to NULL, not TRUE — an `if NULL then`
  -- silently falls through in PL/pgSQL rather than short-circuiting, which
  -- would have let exactly the least-trusted caller reach the count query
  -- below. Caught by testing this as anon locally before shipping it.
  if coalesce(public.atd_role(), '') <> 'admin' then
    return 0;
  end if;
  select count(*) into v_count from public.login_attempts
  where locked_until is not null and locked_until > now();
  return v_count;
end;
$$;

-- --- Family 9: audit log — anyone signed in can append, only admin reads --
-- A failed login attempt is, by definition, NOT signed in — auth.uid() is
-- null for it, since no session was ever established. The original
-- "auth.uid() is not null" check alone made every login.failed audit entry
-- fail this same way (RLS violation on kv_store, visible in the Postgres
-- logs), silently losing exactly the security-relevant record — repeated
-- failed logins — that a government pilot's audit trail most needs to
-- keep. Widened to also allow an anonymous append specifically when the
-- record's own action is 'login.failed'; every other action still requires
-- a real session, so this doesn't open up any other anonymous write.
create policy "kv_store: authenticated append to audit log" on public.kv_store
  for insert with check (
    prefix = 'auditLog'
    and (auth.uid() is not null or (value->>'action') = 'login.failed')
  );
create policy "kv_store: admin reads audit log" on public.kv_store
  for select using (prefix = 'auditLog' and public.atd_role() = 'admin');
-- systemError / platform / role prefixes are intentionally left admin-only —
-- covered already by the "admin full access" policy above, no separate
-- policy needed since no other role should touch them at all.

-- ----------------------------------------------------------------------------
-- 3. Storage — replacing base64-in-JSON with real object storage.
-- ----------------------------------------------------------------------------
-- Run this next part from the Supabase dashboard's Storage UI (create a
-- bucket named application-files, private) or via the SQL below if the
-- storage extension is enabled on your project.

insert into storage.buckets (id, name, public)
values ('application-files', 'application-files', false)
on conflict (id) do nothing;

-- Mirrors the kv_store application-lifecycle policy: the owning applicant,
-- the receiving Municipal Corporation, and their JCF counterpart can read;
-- only the applicant (on their own folder) can write.
create policy "storage: poa manage own files" on storage.objects
  for all using (
    bucket_id = 'application-files'
    and public.atd_role() = 'poa'
    and (storage.foldername(name))[2] = auth.uid()::text
  ) with check (
    bucket_id = 'application-files'
    and public.atd_role() = 'poa'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "storage: admin full access" on storage.objects
  for all using (bucket_id = 'application-files' and public.atd_role() = 'admin')
  with check (bucket_id = 'application-files' and public.atd_role() = 'admin');

-- Muni/JCF read access to application files is granted through short-lived
-- signed URLs generated server-side by the adapter after the corresponding
-- kv_store row check already passed, rather than a broad storage policy —
-- simpler to reason about than re-deriving muniId from a folder path.

-- ============================================================================
-- End of schema. See SETUP.md in this same folder for what to do with this
-- file, and atd_supabase_adapter.js for the drop-in window.storage
-- replacement that talks to the table defined above.
-- ============================================================================
