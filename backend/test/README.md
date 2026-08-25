# Backend regression suite

Phase B of the [hardening plan](../SETUP.md): every fix verified against a
real local Postgres instance during this engagement was checked once, by
hand, with a throwaway script that got deleted afterward. That's fast, but
it means the next change can quietly re-break something already fixed once
— which is exactly the pattern behind several of the bugs this engagement
found (see `SETUP.md`'s numbered fix history). This directory is those
scripts, kept instead of discarded, organized so they run automatically
instead of only when someone remembers to.

## Running it

```bash
cd backend/test
./run_tests.sh
```

By default this connects the way local development on this machine already
does — `sudo -u postgres psql`, peer authentication, no password. Against a
different Postgres (including the one GitHub Actions spins up — see
`.github/workflows/db-tests.yml` in the repo root), set the standard `PG*`
environment variables and it connects directly instead:

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres ./run_tests.sh
```

Either way it: creates a scratch database (`atendify_test` by default,
override with `ATD_TEST_DB`), loads `pg_stub.sql`, applies
`supabase_schema.sql` fresh, runs every `NNN_*.sql` file in this directory
in order, applies `phase1b_migration.sql` twice as an idempotency check,
then drops the scratch database. It prints a pass/fail count and exits
non-zero if anything failed — that's what CI checks.

## What's actually in here

**`pg_stub.sql`** — a minimal stand-in for the pieces of Supabase's
`auth`/`storage` schemas the app's own schema touches: `auth.users`,
`auth.uid()`/`auth.email()` (backed by a settable session variable instead
of a real JWT, so a test can impersonate any user), `storage.buckets`,
`storage.objects`, and `storage.foldername()`. Also defines the two
assertion helpers every test file uses:

- `test_assert(condition, message)` — raises a real Postgres error (and
  therefore a non-zero `psql` exit code) if `condition` isn't true.
- `test_assert_raises(query, message)` — asserts that running `query`
  raises an error, for the "this must be rejected" half of an RLS test.

**The synthetic `anon` / `authenticated` roles** — created here too,
mirroring the two roles PostgREST/Supabase actually use, so a test can
`set role anon;` or `set role authenticated;` plus
`select set_config('atd_test.uid', '<uuid>', false);` to run a query
exactly as a specific real caller would, RLS and all.

**One important gotcha, learned the hard way while writing these**: the
`atd_test.uid`/`atd_test.email` settings are session-level, not tied to
`SET ROLE`. A test file that impersonates one user and later switches to
`anon` (or a different user) in the *same file* must explicitly clear them
first —

```sql
select set_config('atd_test.uid', '', false);
select set_config('atd_test.email', '', false);
```

— or the earlier identity silently leaks into the later block. This
actually happened writing `080_general_rls_boundaries.sql`; the fix is now
both in that file and in `auth.uid()`/`auth.email()` themselves (`nullif`
against an empty string, so clearing to `''` reads back as genuinely unset
instead of crashing on an empty-string-to-uuid cast).

**The numbered test files** — each one is a regression test for a specific,
real bug found and fixed during this engagement, not a hypothetical:

| File | Regression for |
|---|---|
| `001_fresh_install_smoke.sql` | The schema applying cleanly at all |
| `010_signup_role_assignment.sql` | Fix #4 — the composite-NULL check that sent every pre-authorized signup to the wrong role |
| `020_seed_flags_public_read.sql` | Fix #7/#10 — the 5 seed-completion flags anon must be able to read, and nothing else in that prefix |
| `030_auditlog_anonymous_insert.sql` | Fix #9 — anonymous `login.failed` audit entries allowed, everything else still rejected |
| `040_poa_reupsert_applications.sql` | Fix #11 — applicants can re-save (not just create) their own applications, and only their own |
| `050_jcfd_family5_records.sql` | Fix #8 — JCF officer records scoped to one's own branch |
| `060_invite_provisioning_repair.sql` | The CEO/Chief invite-provisioning gap and its retroactive repair (fix #6's logic) |
| `070_login_lockout.sql` | Fix #12 — server-side lockout enforcement, including the exact `NULL <> 'admin'` bug this suite would have caught automatically (see below) |
| `080_general_rls_boundaries.sql` | Baseline "can't read someone else's / can't read at all" invariants across `profiles` and `staff_invites` |
| `090_jcf_application_scoping.sql` | Fix #13 — a JCF division's own Chief can read/update their jurisdiction's `jcfApplication`/`jcfApplicationFiles`/`jcfWatchlist` records, a different division's Chief and anon cannot, and `atd_jcf_jurisdiction_muni_id()` resolves through `agency:{id}` (not the never-written `jcfBranch:{id}`) |

**Proof this actually catches something, not just passes trivially**: the
`atd_count_active_lockouts()` bug from fix #12 (`if atd_role() <> 'admin'`,
which is `NULL` — not `TRUE` — for a caller with no profile at all, so the
guard silently failed open) was reintroduced into a scratch copy of
`supabase_schema.sql` and the suite was re-run against it before this
directory was ever delivered: `070_login_lockout.sql` failed with a clear
assertion message, the run exited non-zero, and reverting the fix brought
it back to a clean pass. That's the whole point of this directory existing.

## Adding a new test

Next numbered file, same pattern: set up the minimum data needed (as the
superuser connection, before switching role), `set role anon;` or
`set role authenticated;` plus `set_config` to impersonate the caller under
test, then `test_assert`/`test_assert_raises` the behavior that matters —
and `reset role;` (and clear `atd_test.uid`/`atd_test.email` if the same
file later impersonates someone else or drops to anon) when done. When a
new bug gets fixed anywhere in `supabase_schema.sql` or
`phase1b_migration.sql`, the right move is to add its regression test here
in the same round, not just verify it by hand and move on.

## Wiring into CI

`.github/workflows/db-tests.yml` (repo root) runs this suite against a real
`postgres:16` service container on every push and pull request touching
`backend/**`. Nothing else to configure — the workflow sets the `PG*`
environment variables `run_tests.sh` already knows how to use.
