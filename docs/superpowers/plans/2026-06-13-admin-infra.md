# Carbonmice Admin — Plan 4b/4: Infra & Deployment Hardening (DEFERRED)

> **Status: DEFERRED — not locally verifiable.** This work is build-/deploy-time only; the test
> suite cannot prove it correct. Execute when a deploy target is chosen. CI is intentionally
> NOT included (see decision below). Plan 4a (code hardening) is the locally-verifiable half and
> ships first.

**Why separate from 4a:** every item here either touches a production database role, produces a
container image, or wires a scheduler — none can be green-lit by `bin/rails test`. Bundling them
with TDD tasks would let unverifiable work hide behind a green suite.

**Decision (2026-06-13):** CI provider deferred. The roadmap text said "GitLab CI mirroring the
team pipeline," but the repo's `origin` is `github.com:japman/carbonmice-admin`. Resolve which is
authoritative (and whether this GitHub repo is the deploy source or a mirror) before writing CI.

---

## Item 1: Rails Dockerfile + local-dev compose — DONE (2026-06-13)

Shipped on branch `feat/admin-docker`:
- `Dockerfile` — multi-stage (`base` → `build` → `development` / `build_prod` → `production`).
  `development` installs all gem groups; `production` is slim, non-root, assets precompiled
  (`SECRET_KEY_BASE_DUMMY=1 assets:precompile`), `bin/docker-entrypoint` applies admin-only
  `db:migrate` on boot (never `public`). build stage needs `libyaml-dev`/`libffi-dev` (psych/ffi).
- `docker-compose.yml` — local dev, **no db service**; `web` (waits for pg → admin `db:migrate`
  → `rails server -b 0.0.0.0`) + `css` (`tailwindcss:watch`), source bind-mounted. Attaches to the
  Go side's Postgres over the **external `sit` network** (`${SIT_NETWORK:-carbonmice-main-go-be_sit}`),
  service host `postgres`, shared DB `carbon-mice`.
- `.dockerignore`, README "Docker (local dev)" section.
- **Verified end-to-end** (Go compose up): build OK, stack up, `/` → 302 → `/session/new` login
  renders, `admin` schema + tables (incl. `solid_cache_entries`) created in the shared DB, Go
  `public` (60 tables) untouched.

Remaining for deploy: a real registry/build pipeline + the production `/up` healthcheck smoke against
staging; Thruster fronting puma once `bin/thrust` is binstubbed.

### Original notes

- Multi-stage build (build deps → slim runtime), Ruby 4.0.0, `bundle install --without
  development test`, precompiled assets (`propshaft` + `tailwindcss-rails`), `thruster` fronting
  `puma` (the `thruster` gem is already in the Gemfile).
- `.dockerignore` excluding `.git`, `log`, `tmp`, `test`, `docs`, `node_modules`.
- Honor `schema_search_path: "admin,public"` at runtime; image must NOT run `db:prepare` against
  `public` (Go owns it) — only `admin` migrations. Entrypoint runs `db:migrate` scoped to admin
  migrations, never `db:schema:load`.
- **Verify:** `docker build` succeeds; container boots, `/up` healthcheck 200, login works against
  a staging DB. (Build-time + manual smoke only.)

## Item 2: Dedicated least-privilege DB role — DONE (2026-06-13)

Shipped under `db/roles/` (`least_privilege.sql`, `verify.sql`, `README.md`):
- **Two roles** (not one): `carbonmice_admin_migrator` owns the `admin` schema + runs
  migrations; `carbonmice_admin_app` is the limited runtime role. The split is what makes
  the audit REVOKE enforceable — the app role is not the table owner.
- App grants: full DML on `admin` except `audit_logs` (SELECT/INSERT only — append-only) and
  `solid_cache_entries` (full DML kept, no REVOKE bleed); `public` = SELECT everywhere it reads,
  +UPDATE on the 5 write tables, +INSERT on `carbon_emission_factors` only, never DELETE/DDL.
- **Verified end-to-end** against the running dev Postgres via `SET ROLE` + a rolled-back
  battery: all allowed ops succeeded; UPDATE/DELETE on `audit_logs` and DELETE/INSERT/CREATE/ALTER
  on `public` all rejected with `insufficient_privilege`. Test roles dropped afterward.
- Remaining for deploy: set passwords per env; run migrations as the migrator role (separate
  DATABASE_URL from the runtime `DB_*`); point runtime `DB_USER=carbonmice_admin_app`.

### Original spec

- New role with FULL privileges on the `admin` schema (app-owned) and only the needed
  table-level `SELECT`/`INSERT`/`UPDATE` grants on the specific `public` (Go) tables the app
  reads/writes — never `CREATE`/`DROP`/`ALTER` on `public`.
- `REVOKE UPDATE, DELETE ON admin.audit_logs FROM <app_role>` so the application can append audit
  rows but never rewrite or erase them (append-only audit trail). The purge/maintenance role, if
  any, is separate.
- **Do NOT let the audit-log REVOKE bleed onto `admin.solid_cache_entries`** (added in Plan 4a):
  Solid Cache writes via `upsert_all` and sweeps expired rows, so the app role legitimately needs
  `INSERT, SELECT, UPDATE, DELETE` on `admin.solid_cache_entries`. Grant those explicitly; the
  append-only constraint applies to `audit_logs` only.
- Deliver as a reviewed SQL script under `db/roles/` + README runbook; applied manually by a DBA
  with superuser. Do NOT put role DDL in a Rails migration (migrations run as the app role).
- **Verify:** in staging, confirm the app role cannot `UPDATE`/`DELETE` `audit_logs` (expect
  permission denied) and cannot DDL `public`; the app's normal flows still pass.

## Item 3: Schedule `admin:purge_sessions` — DONE (2026-06-13), runtime gated on pg fix

Implemented with **Solid Queue recurring tasks** (Rails-native, DB-backed — consistent with the
Solid Cache decision, no external cron):
- `solid_queue` wired to the PRIMARY connection (single-DB); 11 `solid_queue_*` tables created in
  the `admin` schema via a normal migration (installer's standalone schema deleted, like Solid
  Cache). `db/structure.sql` regenerated — `public` byte-unchanged (verified against the live DB).
- `PurgeSessionsJob` wraps `Session.older_than(ADMIN_SESSION_TTL_DAYS, default 30).delete_all`.
- `config/recurring.yml` (production only): `purge_sessions` daily at 3am + the installer's
  `clear_solid_queue_finished_jobs` hygiene task. Both schedules asserted Fugit-parseable by a test.
- Production runs the supervisor **in-Puma** via `plugin :solid_queue if SOLID_QUEUE_IN_PUMA` — no
  separate worker process; `config.active_job.queue_adapter = :solid_queue`.

**Verified (job + schema):** `solid_queue_*` tables land in `admin` (not `public`);
`PurgeSessionsJob.perform_now` against the live shared Postgres purged a 40-day-old session and kept
a fresh one; unit + schedule tests green (149 suite).

**Verified (live worker, on Linux):** running `bin/jobs` **inside the Linux app container** on the
shared `sit` network — twice — the Solid Queue supervisor + scheduler booted, the recurring
`purge_sessions` task fired, and `DELETE FROM sessions WHERE updated_at <= …` purged the seeded
stale session. Ran the full duration with **zero segfaults**. So the worker is production-ready.

**macOS-dev-host caveat (not a production gate):** running the supervisor *natively on the macOS
host* (`bin/jobs` outside Docker) crashes with a **pg 1.6.3 + Ruby 4.0.0 fork segfault** — the same
bug behind `parallelize(workers: 1)` in `test_helper.rb`. It is **host-specific**: the Linux
container does NOT hit it (verified above), and `bundle update pg` is a no-op (1.6.3 is already the
latest release). Implication: run the scheduler in the container / production image, never natively
on macOS. (The parallel-test workaround likewise only matters for local macOS runs; Linux CI could
re-enable parallel workers — left as a separate change since `bin/rails test` is also run on the
Mac.)

## Item 4: CI (BLOCKED on provider decision)

- Once decided: pipeline mirrors the local gate — `bin/rails test`, `bin/rails test:system`,
  domain standalone, `rubocop`, `brakeman` — plus the Docker build from Item 1. Postgres service
  must load `core_structure.sql` (Go `public` fixture) before the suite, same as `test_helper.rb`.

---

## Notes carried from Plan 4a review backlog (already DONE in 4a)

- Advisory lock on tier updates ✓ (4a Task 3)
- EF form re-render on error ✓ (4a Task 2)
- Recent-activity through the audit port ✓ (4a Task 1)

## Optional follow-ups noted during 4a

- **Offset advisory-lock granularity:** `ArOffsetPricingTierRepository#advisory_lock!` takes one
  table-wide lock, but the offset overlap check is scoped per `carbon_offset_source_id`. This
  over-locks (edits to different sources serialize needlessly) — strictly safe, negligible at
  admin write volume. If contention ever matters, key the lock by source id
  (`pg_advisory_xact_lock(LOCK_KEY, source_hash)`).

## Still deferred

- Re-enable parallel test workers (`parallelize(workers: :number_of_processors)`) once the pg gem
  fixes the Ruby 4.0 fork segfault — tracked in `test/test_helper.rb`.
- Tier create/delete UI if operationally needed.
