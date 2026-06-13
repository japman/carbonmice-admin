-- Verify the carbonmice_admin_app role's privileges by impersonating it with
-- SET ROLE. Everything runs inside a transaction that ROLLs BACK, so no data
-- changes. Run as a superuser AFTER least_privilege.sql:
--     psql "$ADMIN_SUPERUSER_URL" -f db/roles/verify.sql
-- A failed expectation RAISEs and aborts (ON_ERROR_STOP), so a clean run = pass.

\set ON_ERROR_STOP on
BEGIN;

-- ===== ALLOWED operations (must all succeed under the app role) =====
SET ROLE carbonmice_admin_app;

\echo '-- allowed: read public, read admin'
SELECT 1 FROM public.units LIMIT 1;
SELECT 1 FROM admin.audit_logs LIMIT 1;

\echo '-- allowed: append audit_logs (needs INSERT + sequence USAGE)'
INSERT INTO admin.audit_logs (action, created_at) VALUES ('rolecheck.allowed', now());

\echo '-- allowed: UPDATE public write tables (privilege checked even WHERE false)'
UPDATE public.events                 SET event_status = event_status WHERE false;
UPDATE public.carbon_emission_factors SET source      = source       WHERE false;
UPDATE public.users                  SET event_quota  = event_quota  WHERE false;
UPDATE public.carbon_categories      SET name_thai    = name_thai    WHERE false;

\echo '-- allowed: INSERT a new emission factor (uuid PK, no sequence)'
INSERT INTO public.carbon_emission_factors
  (name, source, value_per_unit, unit_title, carbon_category_id, created_by)
  SELECT 'rolecheck', 'rolecheck', 1, 'rc', carbon_category_id, 'rolecheck'
  FROM public.carbon_emission_factors LIMIT 1;

\echo '-- allowed: upsert solid_cache_entries (INSERT + UPDATE via ON CONFLICT)'
INSERT INTO admin.solid_cache_entries (key, value, key_hash, byte_size, created_at)
  VALUES ('\x726f6c65'::bytea, '\x01'::bytea, 424242, 1, now())
  ON CONFLICT (key_hash) DO UPDATE SET value = EXCLUDED.value;

RESET ROLE;
\echo '== ALLOWED ops all succeeded =='

-- ===== DENIED operations (each must raise insufficient_privilege) =====
SET ROLE carbonmice_admin_app;

DO $$
DECLARE
  probes text[] := ARRAY[
    'UPDATE admin.audit_logs SET action = action WHERE false',
    'DELETE FROM admin.audit_logs WHERE false',
    'DELETE FROM public.events WHERE false',
    $q$INSERT INTO public.events (event_status) VALUES ('rc')$q$,
    'CREATE TABLE public.rolecheck_tmp (id int)',
    'ALTER TABLE public.events ADD COLUMN rolecheck_tmp int'
  ];
  stmt text;
BEGIN
  FOREACH stmt IN ARRAY probes LOOP
    BEGIN
      EXECUTE stmt;
      RAISE EXCEPTION 'DENY-CHECK FAILED: app was ALLOWED to run: %', stmt;
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS deny: %', stmt;
    END;
  END LOOP;
END $$;

RESET ROLE;
\echo '== DENIED ops all correctly rejected =='

ROLLBACK;
\echo '== verify.sql complete: rolled back, no data changed =='
