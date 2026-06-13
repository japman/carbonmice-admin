# Least-privilege database roles (Plan 4b, Item 2)

The admin app shares the carbonmice Postgres with the Go backend. In production it
must connect with a role that can do exactly what the app needs and nothing more —
in particular it must **never** be able to rewrite the audit trail or touch the
Go-owned `public` schema's structure.

These scripts are run by a DBA per environment. They are **not** Rails migrations:
role/grant DDL is cluster-wide and outlives any single deploy.

## Two roles

| Role | Purpose | Connects as |
|------|---------|-------------|
| `carbonmice_admin_migrator` | Owns the `admin` schema, runs `db:migrate`. Full DDL on `admin`. No access to `public`. | the deploy/migration step |
| `carbonmice_admin_app` | The **runtime** web process. Limited DML only. | the running Puma server |

Splitting them is what makes the append-only audit guarantee real: because the app
role does **not own** `admin.audit_logs`, the `REVOKE UPDATE, DELETE` on it is
actually enforced (an owner would bypass it).

## Privilege matrix (what `carbonmice_admin_app` gets)

**`admin` schema (app-owned):** `SELECT, INSERT, UPDATE, DELETE` on all tables and
`USAGE, SELECT` on all sequences — **except**:
- `admin.audit_logs` → `SELECT, INSERT` only (append-only; no UPDATE/DELETE).
- `admin.solid_cache_entries` → full DML kept (Solid Cache upserts and sweeps).

**`public` schema (Go-owned):** `USAGE` + table-level only, never DDL, never DELETE:

| public table | app grant |
|--------------|-----------|
| `carbon_emission_factors` | SELECT, INSERT, UPDATE |
| `event_pricing_tiers`, `carbon_offset_pricing_tiers`, `carbon_categories`, `events`, `users` | SELECT, UPDATE |
| `units`, `carbon_emissions`, `carbon_offset_sources`, `event_statuses` | SELECT |

(Edits and soft-deletes are `UPDATE`s, so no `DELETE` is needed. `carbon_emission_factors.id`
is `gen_random_uuid()`, so no `public` sequence grant is needed.)

## Apply

```bash
# 1. Create roles + grants (idempotent).
psql "$ADMIN_SUPERUSER_URL" -f db/roles/least_privilege.sql

# 2. Set login passwords (kept out of the repo).
psql "$ADMIN_SUPERUSER_URL" \
  -c "ALTER ROLE carbonmice_admin_migrator PASSWORD '...';" \
  -c "ALTER ROLE carbonmice_admin_app      PASSWORD '...';"

# 3. Verify the runtime role (impersonates it, rolls everything back).
psql "$ADMIN_SUPERUSER_URL" -f db/roles/verify.sql   # clean run = pass
```

## Wire the app to the roles

- **Runtime** (Puma): `DB_USER=carbonmice_admin_app` (the limited role).
- **Migrations**: run `db:migrate` as `carbonmice_admin_migrator` so it owns the
  admin objects. Either run migrations as a separate deploy step with the migrator
  credentials, or point `bin/docker-entrypoint`'s `db:migrate` at a migrator
  `DATABASE_URL` distinct from the runtime `DB_*`. Do **not** run the runtime app
  as the migrator.

## Verified

`verify.sql` was run against the shared dev Postgres (2026-06-13). Confirmed:
- **Allowed:** read `public`/`admin`, append `audit_logs`, UPDATE all six `public`
  write tables, INSERT a `carbon_emission_factors` row, upsert `solid_cache_entries`.
- **Denied** (`insufficient_privilege`): UPDATE/DELETE `admin.audit_logs`; DELETE,
  INSERT, CREATE TABLE, and ALTER TABLE on `public`.
All inside a rolled-back transaction — no data changed.
