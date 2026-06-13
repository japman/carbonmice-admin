-- carbonmice-admin — least-privilege database roles (Plan 4b, Item 2)
--
-- Run ONCE per environment as a superuser (or the database owner):
--     psql "$ADMIN_SUPERUSER_URL" -f db/roles/least_privilege.sql
--
-- This is NOT a Rails migration — role/grant DDL is environment-wide and is
-- managed by a DBA, not by app deploys. It is idempotent (safe to re-run).
--
-- Two roles:
--   carbonmice_admin_migrator — owns the `admin` schema and runs migrations
--                               (point `db:migrate` at this role). Never granted
--                               anything on the Go-owned `public` schema.
--   carbonmice_admin_app       — the RUNTIME web role. Limited privileges only.
--                               Because it does NOT own the admin tables, the
--                               append-only REVOKE on audit_logs is enforced.
--
-- Set login passwords per environment AFTER running this (not stored here):
--     ALTER ROLE carbonmice_admin_migrator PASSWORD '...';
--     ALTER ROLE carbonmice_admin_app      PASSWORD '...';

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 1. Roles (idempotent; created NOLOGIN-safe, you add a password to enable login)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'carbonmice_admin_migrator') THEN
    CREATE ROLE carbonmice_admin_migrator LOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'carbonmice_admin_app') THEN
    CREATE ROLE carbonmice_admin_app LOGIN;
  END IF;
END $$;

-- CONNECT on whatever database this is run against (shared `carbon-mice`).
DO $$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO carbonmice_admin_migrator', current_database());
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO carbonmice_admin_app',      current_database());
END $$;

-- ---------------------------------------------------------------------------
-- 2. admin schema — owned by the migrator (fresh DB only; no-op if it exists)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM information_schema.schemata WHERE schema_name = 'admin') THEN
    EXECUTE 'CREATE SCHEMA admin AUTHORIZATION carbonmice_admin_migrator';
  END IF;
END $$;

-- Migrator: full control of the admin schema (DDL for migrations).
GRANT USAGE, CREATE ON SCHEMA admin TO carbonmice_admin_migrator;
GRANT ALL ON ALL TABLES    IN SCHEMA admin TO carbonmice_admin_migrator;
GRANT ALL ON ALL SEQUENCES IN SCHEMA admin TO carbonmice_admin_migrator;

-- ---------------------------------------------------------------------------
-- 3. Runtime app role — admin schema (full DML, then audit_logs append-only)
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA admin TO carbonmice_admin_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA admin TO carbonmice_admin_app;
-- INSERTs into sequence-backed admin tables (e.g. audit_logs.id) need sequence USAGE.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA admin TO carbonmice_admin_app;

-- Future admin tables/sequences created by the migrator inherit the same grant.
ALTER DEFAULT PRIVILEGES FOR ROLE carbonmice_admin_migrator IN SCHEMA admin
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO carbonmice_admin_app;
ALTER DEFAULT PRIVILEGES FOR ROLE carbonmice_admin_migrator IN SCHEMA admin
  GRANT USAGE, SELECT ON SEQUENCES TO carbonmice_admin_app;

-- audit_logs is APPEND-ONLY: the app may read and append, never rewrite/erase.
-- (Enforced because the app role is not the table owner.)
REVOKE UPDATE, DELETE ON admin.audit_logs FROM carbonmice_admin_app;

-- solid_cache_entries legitimately needs full DML (upsert writes + expiry sweep).
-- The blanket grant above already covers it and the audit REVOKE did NOT touch it;
-- re-stated explicitly so the intent survives future edits to this script.
GRANT SELECT, INSERT, UPDATE, DELETE ON admin.solid_cache_entries TO carbonmice_admin_app;

-- ---------------------------------------------------------------------------
-- 4. Runtime app role — public (Go-owned) schema: least privilege, no DDL
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO carbonmice_admin_app;

-- Read-only reference tables.
GRANT SELECT ON
  public.units,
  public.carbon_emissions,
  public.carbon_offset_sources,
  public.event_statuses
  TO carbonmice_admin_app;

-- Read + UPDATE (edits and soft-deletes are UPDATEs; no INSERT, no DELETE).
GRANT SELECT, UPDATE ON
  public.event_pricing_tiers,
  public.carbon_offset_pricing_tiers,
  public.carbon_categories,
  public.events,
  public.users
  TO carbonmice_admin_app;

-- Read + INSERT + UPDATE — the only public table the app creates rows in.
-- (id is gen_random_uuid(), so no public sequence grant is required.)
GRANT SELECT, INSERT, UPDATE ON public.carbon_emission_factors TO carbonmice_admin_app;

-- The app never needs DELETE or DDL on public, and never CREATE in public.
-- On PostgreSQL 15+ the public schema does not grant CREATE to PUBLIC by default,
-- so no extra REVOKE is needed; verify with: \dn+ public
