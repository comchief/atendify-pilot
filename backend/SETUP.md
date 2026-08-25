# Standing up Atendify's shared backend — Supabase

## Why Supabase

The pilot-readiness assessment's top blocker was that every Atendify portal
reads and writes `window.localStorage` — nothing is shared between devices.
Fixing that means putting a real, shared database behind the app. Rather than
hand-rolling a server, the recommendation is a **managed backend-as-a-service**,
and specifically **Supabase**, for three reasons that matter for this project
in particular:

1. **Postgres, not a NoSQL store.** Atendify's data is inherently relational
   (applications belong to venues belong to municipalities; JCF filings link
   back to POA applications by number) even though it's stored today as
   loose JSON blobs. Supabase gives a real relational database now and a
   clean path to properly normalize later, without a platform migration.
2. **Row Level Security built into the database itself.** Every portal's
   access rules (a municipal officer only sees their own agency, a JCF
   division only sees its own jurisdiction, an applicant only sees their own
   filings) can be enforced as Postgres policies rather than trusted to
   client-side JavaScript — which matters because right now those rules
   *are* only client-side. `supabase_schema.sql` in this folder implements
   this directly.
3. **Auth and file storage included, and no lock-in.** Supabase's Auth
   replaces the current hardcoded/plaintext passwords with real hashed
   credentials, and its Storage (S3-compatible) replaces the base64-in-JSON
   file uploads flagged as a quota risk. Supabase is also open-source and
   self-hostable — if data residency ever becomes a hard requirement for a
   government system, the same schema and RLS policies move to a
   self-hosted instance without a rewrite. Firebase does not offer that
   option; it's Google-hosted only, and its NoSQL model fights this app's
   relational shape.

Appwrite was the other serious contender (also self-hostable, also
relational-ish), but Supabase's Postgres-native RLS is the better fit given
how much of this app's access logic already reasons about roles, agencies,
and jurisdictions.

## What's in this folder

- **`supabase_schema.sql`** — creates the shared table (`kv_store`, a
  structured stand-in for the current localStorage shim), the `profiles` /
  `staff_invites` tables that map real people to roles, and the Row Level
  Security policies that enforce who can read and write what. Read the
  comments at the top — this is a deliberate "lift and shift" of the
  existing data shape, not a full re-normalization, and the file explains
  why that's the right call for a first pilot.
- **`atd_supabase_adapter.js`** — a drop-in replacement for the
  `window.storage` object already inside `atendify.html`, built to the exact
  same four-method interface (`get`/`set`/`delete`/`list`) so the ~1,000
  places in the app that already call it do not need to change. It also
  transparently moves large file uploads (photo ID, event fliers, payment
  receipts) out of the JSON blob and into real object storage.

Neither file has been wired into `atendify.html` yet — see "What happens
after you send me the keys" below for why that's a deliberate, separate step.

## Steps to take (roughly 15 minutes)

1. **Create a Supabase project.** Go to supabase.com, sign up or sign in,
   and create a new project. Pick a name like `atendify-pilot`, a database
   password (save it somewhere safe — you likely won't need it day to day,
   but it's the master password if you ever connect a SQL client directly),
   and a region. Pick whatever region is geographically closest to where
   your pilot Municipal Corporation and JCF division actually are — if data
   residency within Jamaica specifically turns out to be a hard requirement,
   flag that back to me and we plan the self-hosted path instead of the
   managed one; nothing above assumes that's ruled out, it's just not
   confirmed as a requirement yet.
2. **Run the schema.** In the project dashboard, open the SQL Editor, paste
   in the entire contents of `supabase_schema.sql`, and run it once. The
   tables and seed data are safe to re-run (`create table if not exists` /
   `on conflict do nothing`), but the security policies are not — running
   the whole file a second time on a project that already has them fails
   with "policy already exists." If you've already run this file once and
   just need to pick up a later change, run the small, safe
   `phase1b_migration.sql` in this same folder instead of the whole file.
3. **Grab two values.** In Project Settings → API, copy the **Project URL**
   and the **`anon` public key** (not the `service_role` key — that one
   must never be shared or used client-side; it bypasses every RLS policy
   this schema just set up).
4. **Send those two values back to me** in this conversation (or store them
   somewhere and tell me where). I'll take it from there: wiring the
   adapter into `atendify.html` behind a small config flag, rewriting each
   portal's login flow to use real Supabase Auth instead of the seeded
   passwords, and testing the whole thing end to end with multiple
   simulated devices before calling it pilot-ready — the same way every
   other change to this app has been tested this whole project.

## Phase 1b — the login/Auth rewrite (done)

Every portal's login (Admin, Municipal officer, JCF staff, and the public
POA/applicant account system) now checks real Supabase Auth credentials
instead of the old hardcoded/shared demo passwords, whenever a Supabase
backend is configured — with the original demo-password behavior kept as
the fallback so the app still works unmodified in a sandboxed preview.
Ownership of POA and JCF applications uses the field the app already wrote
on every record — `ownerEmail` — rather than adding a new one, so
`buildApplicationRecord()` and its JCF equivalent needed no changes at all.

**What you need to do once, per real account:**

- **Officers and JCF staff don't exist as real logins yet.** A Municipal
  Corporation CEO or JCF Chief still creates the person's record the same
  way as before (Manage Users / Add Staff) — that now also pre-authorizes
  their email behind the scenes. The person then visits their portal's
  login screen and clicks the small "First time signing in? Create your
  password" link, using the email their CEO/Chief added them with and
  whatever password they choose. From then on, that's their real login.
- **Admin** works the same way: visit the Admin login screen and click
  "Create the admin account" using `admin@gmail.com` (or change the seeded
  email in `supabase_schema.sql`/`phase1b_migration.sql` first if the real
  admin should use a different address) and a real password.
- **If you already ran `supabase_schema.sql` once** before this change, run
  `phase1b_migration.sql` now instead of the whole schema file — see the
  note in step 2 above.
- **Every seeded pilot Municipal/JCF officer is now pre-authorized too** —
  originally only the Admin account was. If you already had officers signing
  up and getting stuck ("Invalid email or password" despite the right
  credentials), that was a real bug (see below) and running
  `phase1b_migration.sql` repairs any account already stuck by it, in
  addition to pre-authorizing everyone going forward.
- **Run `reference_data_seed.sql` once** (new file, see below) — the app's
  agency directory (the 17 municipalities/agencies) and municipal officer
  roster can no longer seed themselves the way they used to; this file loads
  that same data directly. Do this whether you're setting up fresh or
  upgrading an existing project — it's not part of `supabase_schema.sql` or
  `phase1b_migration.sql`, run it separately, any time after either of those.

**A real bug that was found and fixed:** the trigger that assigns a
pre-authorized role at signup checked "is this staff_invites row not null"
on the whole database row — but Postgres only treats a multi-column row as
NOT NULL when *every* column in it is non-null, and every real invite has at
least one null column by design (a muni invite has no `jcf_branch_id`, a
jcfd invite has no `agency_id`, the admin invite has neither). That made the
check false for every invite that ever existed, so every pre-authorized
signup — including the very first Admin one — silently fell through to
"no invite on file" and landed as a public applicant instead. Fixed in both
files; `phase1b_migration.sql` also retroactively repairs any account that
already got stuck this way.

**A second real bug, found right after the first:** the app used to
populate its own agency directory and officer roster by writing them into
storage the first time anyone loaded the public site — harmless under the
old pure-localStorage design, but under real Row Level Security, an
anonymous visitor has no permission to write that data, so this always
failed. Worse, the failure was memoized: once it failed once, the app never
tried again for the rest of that page load, so `admin`'s own dashboard would
show no agencies at all even after logging in — and a related knock-on
effect meant creating a *new* municipality as admin could still throw a Row
Level Security error, left over from that very first failed attempt, even
though the new municipality itself saved correctly. Fixed by (1) making that
seeding logic recover instead of permanently failing, (2) having a Municipal
Corporation officer's real login re-read their own record *after* signing in
rather than relying on data loaded before anyone was authenticated, and (3)
loading the actual agency/officer reference data directly via
`reference_data_seed.sql` instead of depending on an anonymous browser
write to ever succeed.

- **`reference_data_seed.sql`** — the 17-agency directory, 13 seeded
  municipal officers, the 3 role permission templates, the 8 demo venues,
  the 64-row default advertisement price list, and the 1 seeded watchlist
  entry, all generated directly from the same data already in
  `atendify.html`, loaded straight into the database (this bypasses Row
  Level Security entirely, the same way running any file in the SQL Editor
  does, which is exactly why it works where the app's own anonymous writes
  couldn't).

**An on-screen error panel, added so you can self-diagnose without needing
the Supabase logs:** any backend read/write failure — an RLS rejection, a
network error, anything — now shows up directly on the page as a dark red
panel in the bottom-right corner (title "Errors (N)", with Clear/Hide
buttons). This is what surfaced the third bug below; if anything unexpected
happens while testing, check that panel first and paste its contents back
rather than needing to open the Supabase dashboard's logs.

**A third real bug, found via that new panel:** the app checks 4 flags
(`platform:agenciesSeeded`, `platform:muniUsersSeeded`,
`platform:demoDataSeeded`, `platform:rolesSeeded`) before attempting each of
its one-time client-side seed writes, to make sure it only ever seeds once.
Those flags live in the admin-only `platform` prefix, though, so anyone who
isn't already authenticated as admin at that exact moment — which in
practice is every anonymous visitor, and even admin's own tab in the brief
window before its session finishes restoring — can't even *read* the flag,
so the check always came back empty and the app retried the (RLS-blocked)
write on every single page load, forever, for everyone. Harmless in effect
(it falls back to local seed data every time) but noisy — this is the "new
row violates row-level security policy for table kv_store" you kept seeing
even though the municipality you created saved correctly. Fixed by adding a
narrow public-read policy for just those 4 boolean/timestamp completion
markers (`phase1b_migration.sql` fix #7 — nothing else in the admin-only
`platform` prefix, like the integrations config, is affected) and loading
the real completed values via the expanded `reference_data_seed.sql` above,
so the check succeeds and the app stops retrying for good.

- **If you already ran `phase1b_migration.sql` before this fix**, run it
  again — it's idempotent — to pick up fix #7, then re-run the updated
  `reference_data_seed.sql` to load the roles/venues/ads/watchlist data and
  mark the two new flags done.

**A fourth issue, not a bug but worth knowing about:** you may occasionally
see `PGRST303 — JWT issued at future` in the error panel. This is a known
Supabase infrastructure quirk — PostgREST's own clock is briefly a few
seconds behind the Auth service's clock right after a token is issued or
refreshed, so a perfectly valid, freshly-issued login token looks like it
was "issued in the future" for a moment (see
[supabase/discussions#48123](https://github.com/orgs/supabase/discussions/48123)).
It's not caused by anything in this app or its Row Level Security policies.
Every backend call now retries once after a short pause if it sees this
specific error, which is normally enough for it to clear on its own; if it
keeps showing up well after that, that's Supabase's own infrastructure
clock drift and needs a support ticket to Supabase, not a change here.

**A fifth real bug:** creating a new JCF agency never made it show up in the
JCF portal's own login screen "Division" dropdown. Unlike Municipal
Corporations — which automatically get a real CEO record the moment
they're created — JCF divisions never got any officer record provisioned at
all, and worse, the entire JCF officer roster (`jcfdStaffUsers`) had never
been connected to the real backend in the first place; it was still the
original hardcoded, in-memory-only demo data from before this app had a
shared database, the same state Municipal officers were in before Phase 1b.
That meant JCF staff added through a Police Chief's "Add Staff" screen were
also silently lost on every page reload and never visible from another
browser or device. Fixed with the same treatment Municipal officers already
got: a real `jcfdUser:{branchId}:{id}` record per officer (RLS fix #8 in
`phase1b_migration.sql`, scoped so a division's own signed-in staff can only
see their own branch's roster), a new agency of type JCF now automatically
gets a real Police Chief record the moment it's created (mirroring the CEO
provisioning Municipal Corporations already had), the JCF login dropdown
itself now reads the real, publicly-readable agency directory directly
instead of depending on which branches happened to already have staff
records, and a signed-in officer's own record is re-read right after
sign-in (the same anonymous-read-under-RLS fix Municipal officers already
had). The 7 already-seeded JCF officers are now in the updated
`reference_data_seed.sql` too.

**While fixing that, the same latent bug was found and fixed on the
Municipal officer login screen before it was ever reported:** its own
municipality dropdown was built the same way — intersected against
`municipalUsers`, which is also loaded anonymously and also comes back empty
under RLS pre-login. It likely hasn't shown up yet only because testing so
far happened while already signed in as admin in the same browser tab
(whose session can read everything); a genuinely fresh visitor would have
seen an empty dropdown. Fixed the same way — the dropdown now reads directly
from the real agency directory instead of intersecting with staff records.

**A sixth bug, a direct miss from the fifth:** the new JCF officer roster
introduced a 5th one-time-seed completion flag,
`platform:jcfdUsersSeeded` — but it didn't get added to fix #7's
public-read policy alongside the other four, so a JCF officer's own real
login (which re-reads that roster right after signing in) hit the exact
same "can't even read the flag, so retries the doomed write" RLS noise fix
#7 was supposed to have already solved. Fixed in `phase1b_migration.sql`
fix #10 and `supabase_schema.sql`; `reference_data_seed.sql` now marks this
flag done too. Also: the error panel now shows a short summary of *what*
was being written (action/portal/actor/agencyId/muniId/branchId, when
present) alongside which key failed, not just the key — so a report like
"storage.set(auditLog:...) failed" comes with enough context on the next
occurrence to diagnose in one round trip instead of several.

**Still not done, called out rather than left implicit:**

- **The login-attempt lockout stays client-enforced.** The `loginAttempts`
  table is deliberately left open (see the comment in `supabase_schema.sql`)
  since it only holds attempt counters, not credentials — but a determined
  attacker could still bypass the lockout by talking to the API directly
  instead of through the app's UI. Real rate limiting belongs in a
  server-side function; reasonable to add later, not a reason to hold up
  everything else.
- **No end-to-end test of the real Auth path exists yet.** The sandbox this
  was built in has no network path to Supabase or to the hosted app itself,
  so this could only be syntax-checked and regression-tested against the
  *fallback* (demo-password) path, which was confirmed unchanged. The real
  Auth path needs a real person clicking through it once to confirm.

**A seventh bug, the real explanation behind the recurring `auditLog` RLS
errors:** three rounds of reports about `storage.set(auditLog:...)` failing
with "new row violates row-level security policy" turned out NOT to be
about the audit-log insert policy at all — that policy was confirmed
correct on the live database (its `login.failed` exception was already in
place, ruling out a stale migration). The actual mechanism, confirmed by
reproducing it directly against a local Postgres instance: every write in
this app goes through an *upsert* (`INSERT ... ON CONFLICT (key) DO
UPDATE`), and Postgres requires a **SELECT** policy — not just an INSERT
policy — to even check whether a conflicting row exists, regardless of
whether one actually does. The audit log's SELECT policy is deliberately
admin-only (only admins should be able to read the trail), so *any*
non-admin write — including the anonymous `login.failed` entries the insert
policy explicitly exists to allow — was failing at that conflict-detection
step, before ever reaching the insert rule that would have allowed it.
Fixed in `atendify.html`: audit-log entries are now written with a plain
`insert` instead of an `upsert`. This is safe because every audit key is a
freshly generated, guaranteed-unique id (see `atdLogAudit`) and is never
legitimately re-saved, so there's no conflict to detect in the first place.

**An eighth bug, found proactively while chasing the seventh — more
consequential, and previously unreported:** the same upsert-needs-a-policy
mechanism has a second half — Postgres also requires an **UPDATE** policy
to be present for the `DO UPDATE` branch to succeed whenever a genuine
conflict *does* occur, separate from whatever INSERT policy let the first
write through. A systematic audit of every policy family for this gap found
that public applicants (`poa`) had insert+select policies for their own
applications and JCF filings, but no corresponding update policy at all.
That meant an application's very first save succeeded (nothing to conflict
with yet), but the SAME application's very next save — paying a fee,
uploading a document, any later step of the applicant's own wizard — would
fail with this exact RLS error the moment it genuinely conflicted with
itself. This is a more serious bug than the audit-log one, since it sits
directly in the public applicant's core workflow rather than in a
background logging call. Fixed with two new policies mirroring the existing
insert conditions — `"kv_store: poa updates own applications"` and
`"kv_store: poa updates own jcf filings"` — added to `supabase_schema.sql`
and as fix #11 in `phase1b_migration.sql`. Both fixes (seventh and eighth)
were verified against a real local Postgres instance: a fresh install with
both changes applies cleanly end to end; a simulated "old" install (missing
fix #11) had `phase1b_migration.sql` applied twice with no errors
(confirming idempotency) and the two new policies were confirmed absent
beforehand and present and working afterward; an anonymous plain insert of
a `login.failed` audit entry succeeds; and an authenticated `poa` user
creating an application and then genuinely re-saving that same application
(changing its status) succeeds only once fix #11's update policy is in
place.

**Action needed for this round:** re-run `phase1b_migration.sql` against
the live database (it's idempotent — safe to run again even though earlier
fixes are already applied) to pick up fix #11's two new update policies.
Nothing else needs re-running.

**A ninth bug — this is the actual, still-open cause of the original "JCF
division doesn't work" report:** every previous JCF-login fix (the fifth
bug above) fixed the dropdown and the roster, but a newly-created Chief (or
Municipal CEO) still couldn't really log in, because `atdProvisionMuniCeo`
and `atdProvisionJcfdChief` — called the moment an agency is created from
the admin screen — never pre-authorized that person's email in
`staff_invites`. Only staff added later through an existing CEO's or
Chief's own "Add Staff" screen got that treatment (`muni_saveUser` /
`jcfd_saveUser` already call `inviteStaff()`); the very first officer an
agency gets, provisioned automatically at agency-creation time, did not.
Without a `staff_invites` row, that person's real Supabase signup (via
"Create your password") falls to `atd_handle_new_user`'s "no invite found"
branch and is silently assigned role `'poa'` — a public applicant account —
instead of `'muni'`/`'jcfd'`. Their login then fails with the generic
"Invalid division/municipality, email, or password" and a `login.failed`
audit entry, with nothing anywhere hinting that the real problem is a
missing invite rather than a wrong password. Every seeded/demo CEO and
Chief happened to work regardless, because their invites were hand-written
directly into `supabase_schema.sql`; any agency created live through the
admin screen never got one. Reproduced directly against a local Postgres
instance: a signup with no matching `staff_invites` row lands as `role =
'poa'`, exactly matching the reported symptom.

Fixed going forward in `atendify.html`: both `atdProvisionMuniCeo` and
`atdProvisionJcfdChief` now call `window.ATDBackend.inviteStaff(...)`
themselves, the same call `saveUser()` already makes for every other staff
member. Any agency created from now on gets its first officer's invite
written automatically, with the correct pre-existing behavior otherwise
unchanged.

**This does NOT fix any agency already created before this update** — the
St. James JCF division (and possibly others) needs a one-off manual
backfill, since `saveAgency()`'s edit path doesn't re-run the provisioning
step. Run this once in the Supabase SQL Editor for each already-affected
agency, replacing the email:

```sql
-- Looks up the agency's own real id from kv_store and backfills the
-- missing staff_invites row for it in one step.
insert into public.staff_invites (email, role, jcf_branch_id, display_name)
select value->>'email', 'jcfd', value->>'id', value->>'contact'
from public.kv_store
where prefix = 'agency'
  and value->>'type' = 'JCF'
  and lower(value->>'email') = lower('stjames.division@jcf.gov.jm')
on conflict (email) do update
  set role = excluded.role, jcf_branch_id = excluded.jcf_branch_id, display_name = excluded.display_name;

-- If this Chief already tried "Create your password" and got stuck as a
-- 'poa' applicant, this repairs them retroactively (harmless / a no-op if
-- they haven't signed up yet — same logic as fix #6, safe to re-run):
update public.profiles p
set role = si.role, agency_id = si.agency_id, jcf_branch_id = si.jcf_branch_id,
    permissions = si.permissions, display_name = coalesce(p.display_name, si.display_name)
from public.staff_invites si
where lower(p.email) = lower(si.email) and p.role = 'poa';
```

The same gap and the same backfill shape apply to any Municipal Corporation
CEO created live before this update — swap `'jcfd'`/`jcf_branch_id`/
`value->>'type' = 'JCF'` for `'muni'`/`agency_id`/
`value->>'type' = 'Municipal Corporation'` and the CEO's email. Verified
both paths (already-signed-up-and-stuck, and not-yet-signed-up) against a
local Postgres instance: the backfill-plus-repair query correctly moves a
stuck `'poa'` profile to the right role and branch/agency id, and a fresh
signup with the invite already in place lands directly in the right role
with no repair step needed.

## Closing out Phase 2: server-side lockout, and failing loud instead of open

The hardening plan that followed the pilot-readiness report named two
remaining Phase 2 gaps. Both are closed now.

**Login lockout is enforced server-side, not just in the browser.** The
lockout policy itself (attempts allowed, lockout duration) was always
correct — the problem was where its counter lived. It used to be a
`loginAttempts:` prefix in `kv_store`, deliberately left open to anonymous
read/write on the reasoning that attempt counts aren't sensitive. That
reasoning missed the actual risk: with direct read/write access to its own
counter, anyone could reset their own lockout at will, or fabricate one for
someone else, by calling the Supabase REST API directly instead of going
through the app's own JavaScript. A lockout that the person it's meant to
slow down can turn off isn't a real lockout.

Fixed by moving both the storage and the enforcement logic server-side: a
new `login_attempts` table with Row Level Security enabled and *no policies
defined on it at all* — the same "deny by default" RLS gives every other
table here — reachable only through three new `SECURITY DEFINER` Postgres
functions (`atd_check_login_allowed`, `atd_record_login_attempt`,
`atd_count_active_lockouts`) that run with the function owner's privileges
regardless of who calls them, the same trust boundary `atd_role()` already
relies on to read `profiles` despite its own RLS. `atendify.html` now calls
these through `client.rpc(...)` instead of reading/writing the old prefix
directly; the admin-configurable policy (max attempts, lockout minutes) is
unchanged and still edited from the same Security screen. This is fix #12
in `phase1b_migration.sql`.

**Caught by testing it, not by inspection:** the first version of
`atd_count_active_lockouts()` checked `if public.atd_role() <> 'admin'`.
`atd_role()` returns `NULL` for a caller with no profile row at all — a
genuinely anonymous request — and `NULL <> 'admin'` evaluates to `NULL`,
not `TRUE`. An `if NULL then` in PL/pgSQL silently falls through instead of
short-circuiting, so the least-trusted possible caller could have reached
the real count. Found by actually calling the function as an anonymous
`anon` role against a local Postgres instance before shipping it, not by
reasoning about the SQL in the abstract — exactly the discipline this
engagement has leaned on throughout. Fixed with `coalesce(public.atd_role(),
'') <> 'admin'`, and verified for all three cases (anonymous, authenticated
non-admin, authenticated admin) before shipping.

**The demo-password/local-storage fallback now fails loud instead of open.**
If the real backend ever fails to initialize, `window.storage` used to fall
back silently to a shared demo password and per-browser storage — genuinely
useful for previewing the interface somewhere with no network access (a
claude.ai Artifact, say), but the worst possible failure mode if it ever
happened quietly in the actual deployed app: real staff and applicants would
keep working, believing their data is shared, while everything they entered
stayed trapped in their own browser alone — the exact "Monday morning"
scenario the original pilot-readiness report described, just triggered by a
failed CDN request (the `supabase-js` script tag not loading) instead of a
missing backend.

Fixed by distinguishing the two cases at runtime: a sandboxed preview
renders inside an iframe; the real deployed site does not
(`window.self !== window.top`). If the backend fails to configure and the
page is *not* inside an iframe, a full-screen, unmissable overlay now blocks
the app instead of letting it continue on the fallback — it explains that
nothing being entered is actually being saved anywhere shared, and offers a
reload button. Inside an iframe (the Artifact preview), the original silent
fallback still applies, since there's nothing real to protect there.

**Action needed for this round:** re-run `phase1b_migration.sql` (idempotent,
verified by running it twice against a simulated pre-fix database) to pick
up fix #12. No `reference_data_seed.sql` changes were needed.

## Phase B: a regression safety net (`backend/test/`)

The hardening plan named this the phase to do first, on the strength of a
pattern: nearly every bug in this file's history was verified once, by
hand, against a throwaway local Postgres database that was then deleted —
a reasonable way to move fast on one fix at a time, but nothing was left
behind to catch a later change quietly re-breaking it. `backend/test/` is
those scripts, kept instead of discarded, plus a runner
(`backend/test/run_tests.sh`) and a GitHub Actions workflow
(`.github/workflows/db-tests.yml`) that runs them on every push and pull
request touching `backend/**`. Full details, including how to add a new
test, are in `backend/test/README.md`.

Ten test files cover: the schema applying at all; fix #4 (the
composite-NULL signup bug); fix #7/#10 (the 5 publicly-readable seed
flags); fix #9 (anonymous `login.failed` audit entries); fix #11 (POA
re-saving their own applications); fix #8 (JCF officer records scoped to
their own branch); the CEO/Chief invite-provisioning gap and its
retroactive repair; fix #12 (server-side login lockout); fix #13 (JCF
officers reading their own division's filings — see below); and a few
baseline "can't read someone else's data" invariants. The runner also
re-applies
`phase1b_migration.sql` twice on top of a fresh install as an ongoing
idempotency check, not just a one-time verification at the moment each fix
shipped.

**This suite already caught a real bug before it shipped, not
hypothetically:** the first version of fix #12's `atd_count_active_lockouts()`
checked `if atd_role() <> 'admin'`, and since `atd_role()` returns `NULL`
for a caller with no profile row at all, `NULL <> 'admin'` evaluates to
`NULL` — which a PL/pgSQL `if` silently treats as false, letting exactly
the least-trusted caller through. Found by testing it as an anonymous role
locally, not by reading the SQL and assuming it was right; fixed with an
explicit `coalesce`. That fix, and the test that guards it going forward,
shipped together. As a further check before delivering this suite, the bug
was deliberately reintroduced into a scratch copy of the schema and the
suite re-run against it — it failed with a clear assertion message and a
non-zero exit code, then passed clean again once reverted. That's the
proof this is a real safety net, not just files that happen to pass.

**Action needed for this round:** add `.github/workflows/db-tests.yml` and
`backend/test/` to the repository (`comchief/atendify-pilot`) — this
session has no push access to it, so both are delivered as files/a zip
rather than committed directly. After that, every push and PR runs the
suite automatically; to run it locally first, see the Running section in
`backend/test/README.md`.

## Fix #13: JCF officers couldn't see their own division's filings

Found while investigating Phase C below, not something Phase C itself asked
for — but severe enough, and directly relevant enough to the pilot, to fix
in the same round rather than just flag for later. Two compounding bugs,
both already present in the very first version of `supabase_schema.sql`
(not something Phase A/B introduced):

1. `atd_jcf_jurisdiction_muni_id()` — the function every "JCF officer sees
   X for their own division's jurisdiction" policy depends on — looked up a
   plain `jcfBranch:{branchId}` record to find which Municipal Corporation a
   division is linked to. The app never actually writes that record (only
   `jcfBranch:{id}:signature` and `jcfBranch:{id}:rolePermissions`); the
   `linkedMuniId` field it needed lives on the division's own
   `agency:{id}` record instead. This function has returned `null` for
   every JCF division, real or demo, since the original schema hand-off.
2. Separately, `jcfApplication` / `jcfApplicationFiles` / `jcfWatchlist`
   were scoped by the same key-based check as `jcfBranch` / `jcfdUser`
   (`key_part2 = ` the division's own branch id) — but `key_part2` for
   those three is the application number or TRN, never a branch id, so that
   check could never match regardless of bug 1.

Net effect: a JCF Chief or officer could sign in and see their own
division's roster just fine, but every Noise Abatement filing routed to
them, every document attached to one, and every entry on their own
division's watch list came back empty — and reviewing/deciding a filing
failed outright. This affects the real, already-created St. James JCF
division exactly as much as the fictional ones, and would have surfaced the
moment anyone actually tried to process a filing through the JCF portal.

Confirmed locally before fixing: a correctly provisioned `jcfd` profile for
a real division, querying a filing that genuinely belongs to that
division's jurisdiction, got 0 rows back; `atd_jcf_jurisdiction_muni_id()`
called directly returned `null`. Fixed by pointing the function at
`agency:{id}` instead of `jcfBranch:{id}`, and giving
`jcfApplication`/`jcfApplicationFiles`/`jcfWatchlist` their own
value-scoped policies (two new `security definer` helpers,
`atd_jcf_application_muni_id()` / `atd_jcf_application_owner_email()`,
resolve `jcfApplicationFiles` access by looking at its sibling
`jcfApplication` record, since the files record itself carries neither a
`muniId` nor an `ownerEmail`). Verified after the fix: the same profile now
reads and updates its own jurisdiction's filing, a different division's
Chief still gets 0 rows, the applicant who filed it still reads their own
attached files, and anon still gets nothing. Regression test:
`backend/test/090_jcf_application_scoping.sql`.

**Action needed for this round:** already in `supabase_schema.sql` (fresh
installs) and `phase1b_migration.sql` (fix #13, for the already-live
project — safe to re-run, same idempotent `drop policy if exists` /
`create or replace function` pattern as every other fix here).

## Phase C: retiring the fictional demo data

The hardening plan's Phase C: remove the 5 fictional Municipal
Corporations (Kingston & St. Andrew, St. Mary, St. James/Montego Bay,
Manchester, Portmore) and their 3 attached JCF/JFB divisions — invented
staff, applications, venues, and ads — one agency at a time, as each real
one comes online, with the invite-provisioning fix (this file's "ninth
bug") confirmed working for every real CEO/Chief first.

This turned out to have two genuinely separate halves, not one:

**The database half — `backend/retire_demo_data.sql`.** A reviewed,
agency-by-agency removal script. It does NOT decide which agencies are
ready or run itself — every `DELETE` block is wrapped in its own
transaction with the `commit;` deliberately commented out, meant to be run
by hand, one agency at a time, only once that agency's real replacement is
confirmed live and staffed. It opens with a STEP 0 diagnostic (any real
CEO/Chief still stuck as `poa` from the ninth bug, independent of anything
below) and a PREVIEW query (exact row counts per agency, no deletes), then
one block per agency. Verified locally against a database loaded with the
real schema, the real RLS policies, and data matching
`reference_data_seed.sql` exactly: STEP 0 correctly flagged a deliberately
stuck-as-`poa` test CEO and correctly reported a correctly-provisioned real
Chief as fine; the Kingston block (the one with two attached JCF/JFB
divisions) and the Portmore block (the one with the sparsest data — no
venues or ad items ever existed for it) were both actually executed and
committed against the test database, confirmed to delete exactly the rows
they should and nothing else — other demo agencies, real agencies, the
shared watchlist, and real user profiles all came through untouched. One
real bug caught by this verification and fixed before delivery: STEP 0's
own query referenced `a.id`/`a.name`/`a.type`/`a.email` directly on
`kv_store`, which has no such columns — the data lives in `kv_store.value`,
so it needed `a.value->>'id'` etc. instead.

This session has no access to the live Supabase project, so nothing in
this file has been run against production. Take a manual export first (see
the file's own header) before running any block for real.

**The client-code half.** Deleting a fictional row from the database does
not, on its own, make it disappear from the running app — the Municipal
officer portal's `applications`, `venues`, `adItems`, and `watchlist`
started life as permanently-hardcoded arrays that coexist with real backend
data forever, via a fetch-and-filter-by-`_fromStorage` merge pattern
(`array = array.filter(x => !fetchedIds.has(x.id))`) that only ever removes
an entry that has a matching row STILL present in the backend — a demo
entry that's been deleted, rather than merely replaced, is never filtered
out and keeps rendering. `atendify.html` now ships with those four arrays
emptied (real data already loads correctly through the existing
`loadSubmittedApplications()`/`loadVenues()`/`loadAdItems()`/
`loadWatchlist()` functions, the same pattern the Admin portal's own
`applications`/`venues` arrays already used after an earlier fix). The
three shared seed arrays behind them — `ATD_AGENCY_SEED`,
`ATD_MUNI_USER_SEED`, `ATD_JCFD_USER_SEED` — are also pruned down to just
the 9 real blank Municipal Corporations (ids 9–17); this only affects a
future fresh install (the live pilot's `platform:agenciesSeeded` etc. flags
are already set, so this can't touch anything already seeded there), and
stops any future deployment from reintroducing the fictional agencies.

**Action needed for this round:** review `backend/retire_demo_data.sql`'s
header and STEP 0 output against the real project before retiring any real
agency, then run each agency's block by hand (uncommenting its `commit;`)
only once that agency's real replacement is live — there is still no
verified backup/recovery path for this database, so exporting first is not
optional.

Everything else already identified in the pilot-readiness report (an
accessibility/Data Protection Act review, and the still-decorative
per-agency fee fields) is sequenced in the follow-up hardening plan as
later phases, not yet started.
