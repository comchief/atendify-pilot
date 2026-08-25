-- ============================================================================
-- Atendify test fixture: a minimal stand-in for the pieces of Supabase's
-- auth/storage schemas that supabase_schema.sql and phase1b_migration.sql
-- touch, plus the synthetic anon/authenticated roles and impersonation
-- helpers used to run RLS policies as a real (non-superuser) caller.
--
-- This is NOT a full Supabase emulation — it exists only so the schema and
-- its policies can be verified against a real local Postgres instance
-- without a live Supabase project. It is the same stub hand-rewritten from
-- scratch for nearly every fix verified during this engagement; this file
-- is that stub, kept instead of thrown away, which is the entire point of
-- this test/ directory (see the hardening plan's Phase B).
--
-- Load this FIRST, before supabase_schema.sql, into a scratch database.
-- ============================================================================

create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique
);

create schema if not exists storage;
create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false
);
-- Real Supabase storage.objects has many more columns; these are the only
-- ones supabase_schema.sql's storage policies actually reference.
create table if not exists storage.objects (
  id bigint generated always as identity primary key,
  bucket_id text,
  name text,
  owner uuid
);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$ select string_to_array(name, '/') $$;

-- auth.uid()/auth.email() read a per-session setting instead of a real JWT,
-- so a test can impersonate any user with `select set_config('atd_test.uid',
-- '<uuid>', false);` after `set role authenticated;`. Left unset (or role
-- left as anon), both return NULL, matching a real anonymous request.
-- nullif matters here: a test that clears its impersonation with
-- set_config('atd_test.uid', '', false) (rather than never setting it at
-- all) would otherwise crash this function on `''::uuid` instead of
-- correctly reading back as an anonymous, uid-less caller.
create or replace function auth.uid() returns uuid
language sql stable as $$ select nullif(current_setting('atd_test.uid', true), '')::uuid $$;
create or replace function auth.email() returns text
language sql stable as $$ select nullif(current_setting('atd_test.email', true), '') $$;

-- ---- Synthetic anon / authenticated roles ---------------------------------
-- Mirrors the two roles PostgREST/Supabase actually use. Broad table grants
-- are intentional and safe here: Row Level Security is what's under test,
-- not the grants — a table with RLS enabled and no policies denies
-- everything regardless of what's granted (see login_attempts).
do $$ begin
  if not exists (select from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;
grant usage on schema public, auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;

-- ---- A tiny, dependency-free assertion helper -----------------------------
-- Plain plpgsql instead of pgTAP: no extension to install, and a failed
-- assertion raises a real Postgres error, so `psql -v ON_ERROR_STOP=1`
-- aborts with a nonzero exit code exactly the way a CI step needs.
create or replace function test_assert(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if condition is not true then
    raise exception 'ASSERTION FAILED: %', message;
  end if;
  raise notice 'ok — %', message;
end;
$$;

-- Convenience: run a query expecting it to raise an error (e.g. an RLS
-- violation). Postgres has no built-in "expect this to fail," so this
-- wraps a query string in its own subtransaction and asserts it errored.
create or replace function test_assert_raises(query text, message text)
returns void
language plpgsql
as $$
begin
  begin
    execute query;
    raise exception 'ASSERTION FAILED (expected an error, got none): %', message;
  exception
    when others then
      if sqlerrm like 'ASSERTION FAILED%' then
        raise;
      end if;
      raise notice 'ok — % (raised: %)', message, sqlerrm;
  end;
end;
$$;
