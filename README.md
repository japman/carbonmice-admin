# Carbonmice Admin

Admin panel for the carbonmice platform. Rails 8.1.3 / Ruby 4.0.0, hexagonal
architecture (`app/domain` = pure PORO + ports, `app/adapters` = ActiveRecord
implementations, controllers/views = web adapter).

## Database rules (important)

- Shares the carbonmice Postgres. This app owns ONLY the `admin` schema.
- NEVER write a migration that touches the `public` schema — it belongs to the
  Go backend (`carbonmice-main-go-be`, goose migrations).
- `structure.sql` is dumped with `--schema=admin --exclude-schema=public` on
  purpose, and `db:drop`/`db:truncate_all` are blocked in development via
  `protected_environments` (escape hatch: `DISABLE_DATABASE_ENVIRONMENT_CHECK=1`).
- Production should use a dedicated DB role: full rights on `admin`,
  table-level grants on `public`.
- If `db:prepare` ever fails on `CREATE SCHEMA admin` ("already exists"),
  recover with `bin/rails db:ensure_admin_schema db:migrate`.
- `pg_dump`/`psql` come from libpq (`brew install libpq`); the dev Postgres is
  PG 17, so use a libpq ≥ 17 (`export PATH="/opt/homebrew/opt/libpq/bin:$PATH"`).

## Setup

1. Start the dev Postgres: `docker compose up -d postgres` in `../carbonmice-main-go-be`.
2. `cp .env.example .env` and fill values (DB creds from the Go repo's `.env`; dev DB name is `carbon-mice`).
3. `bin/setup`
4. Seed the first superadmin: set `SEED_SUPERADMIN_*` in `.env`, then `bin/rails db:seed`.
5. `bin/dev` → http://localhost:3000

## Tests

- Everything: `bin/rails test` (uses its own `carbonmice_admin_test` DB)
- Domain only (no Rails): `ruby -Itest test/domain/**/*_test.rb`

## Security notes

- Sessions are DB-backed with a 30-day absolute lifetime; deactivating an
  admin locks them out on their next request.
- Login is rate-limited (10 attempts / 3 min / IP) via Rails' built-in
  `rate_limit`, which uses `Rails.cache`. **Production must configure a shared
  cache store** (e.g. Redis or solid_cache) — the default file store is
  per-host, so multi-replica deploys would multiply the limit. Behind a proxy,
  `remote_ip` must be configured correctly or all clients share one bucket.
- The audit log (`admin.audit_logs`) is insert-only at the application layer;
  DB-level `REVOKE UPDATE/DELETE` hardening lands with least-privilege grants
  in Phase 2. Visibility is controlled solely by `AdminAuth::AccessPolicy`
  (currently superadmin) — granting other roles later is a one-line change.

## Spec & plans

- Spec: `docs/superpowers/specs/2026-06-12-admin-panel-design.md`
- Plan 1 (this foundation): `docs/superpowers/plans/2026-06-12-admin-foundation.md`
- Phase 2 plan (events / app users / master data / dashboard, `db/core_structure.sql`
  test fixture, Capybara system tests, Dockerfile + GitLab CI) is written after
  this plan is reviewed.
