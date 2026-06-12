# Carbonmice Admin Panel — Design

**Date:** 2026-06-12
**Status:** Approved (sections reviewed in brainstorming session)
**Project:** `carbonmice-admin` — new standalone Rails application, sibling to `carbonmice-main-go-be` and `carbonmice-main-fe`

## 1. Context & Goals

Carbonmice is a carbon-emissions tracking platform for MICE events. The existing system is a Go backend (`carbonmice-main-go-be`) plus a frontend (`carbonmice-main-fe`). There is no admin interface today.

This project adds an **admin panel** as a new, separate Rails application. Admin staff log in with their own accounts and manage operational data: events, app users, emission master data, and a system dashboard.

**Hard constraint:** the Go backend must not be modified in any way. No new endpoints, no schema changes to Go-owned tables, no code changes.

## 2. Decisions (agreed during brainstorming)

| Topic | Decision |
|---|---|
| Data access | Connect directly to the same Postgres database as the Go backend |
| Admin accounts | Separate `admin_users` table owned by Rails; not linked to the app's `users` table |
| Authentication | Rails 8 built-in authentication generator (session + bcrypt); no Devise |
| Roles | `superadmin` / `admin` / `viewer` |
| Architecture | Classic hexagonal (Ports & Adapters) with a pure-PORO domain layer, inside a modular monolith |
| Phase-1 scope | Events (incl. status changes), app users, master data (emission factors / categories / units / pricing tiers), dashboard, audit log viewer |
| Delivery layer | DHH-style: ERB + Hotwire (Turbo/Stimulus), importmap (no Node build), Minitest, minimal gems |
| Audit log | Every write to Go-owned tables **and every auth event** (login success/failure, logout) is recorded; viewer page for superadmin |
| UI / Corporate identity | Follow the current carbonmice web CI (see §10); carbon MICE logo; Thai-first UI |

## 3. Stack

- Ruby 4.0.0 (already installed on dev machines)
- Rails 8.1.3
- PostgreSQL — the existing shared instance
- Hotwire (Turbo + Stimulus) via importmap; `tailwindcss-rails` for styling (no Node)
- Minitest + Capybara for tests
- Docker for deployment; GitLab CI following the team's existing pattern

## 4. Database Strategy

One Postgres database, two namespaces:

- **`public` schema** — owned by the Go backend (goose migrations). Rails never migrates anything here.
- **`admin` schema** — owned by Rails: `admin_users`, `sessions`, `audit_logs`, and Rails' own `schema_migrations` / `ar_internal_metadata`.

`database.yml` sets `schema_search_path: "admin,public"`. Name collisions are impossible; the Go backend is unaware the `admin` schema exists.

### Rules for Go-owned tables

1. Mapped by thin ActiveRecord models under `Core::` (`Core::Event`, `Core::User`, `Core::EmissionFactor`, …) with explicit `table_name`. No migrations, no callbacks, no business logic.
2. Writes to Go-owned tables happen **only** inside domain use cases, through a repository port. No controller or view touches `Core::*` directly for writes.
3. Every write to a Go-owned table records an `audit_logs` row: admin user, action, record, old value → new value, timestamp.
4. Fields the Go backend computes or cascades (e.g. precalculated snapshots) are read-only in the adapters.

## 5. Architecture — Hexagonal inside a Modular Monolith

Four modules, each with its own domain logic and ports. Dependency direction: web adapter → domain ← persistence adapter. The domain layer is pure Ruby (no Rails constants) and runs without loading Rails.

```
app/
  domain/                       # PORO only — no Rails
    admin_auth/                 # use cases: authenticate, manage admin accounts
      access_policy.rb          # role → permitted actions
    events/
      change_status.rb          # use case w/ status state machine
      list_events.rb
    app_users/
      adjust_quota.rb
      change_role.rb
    master_data/
      upsert_emission_factor.rb # + categories, units, pricing tiers
    dashboard/
      system_summary.rb
    audit/
      list_entries.rb           # audit log viewer (filter by admin/action/date)
    ports/                      # duck-typed interfaces, contract in comments
      event_repository.rb
      app_user_repository.rb
      emission_factor_repository.rb
      stats_query.rb
      audit_recorder.rb         # record(actor:, action:, target:, changes:) — used by all modules
      audit_log_query.rb
    result.rb                   # shared Result object (success?/failure?/error)
  adapters/
    persistence/                # ActiveRecord implementations of ports
      ar_event_repository.rb
      ar_app_user_repository.rb
      ar_emission_factor_repository.rb
      ar_stats_query.rb
      ar_audit_recorder.rb
      ar_audit_log_query.rb
  models/
    core/                       # Go-owned tables (read mapping only)
    admin_user.rb               # Rails-owned
    session.rb
    audit_log.rb
  controllers/                  # web adapter
  views/                        # ERB + Turbo
```

**Module boundaries:** modules talk to each other only through use cases, never by reaching into another module's repositories. Phase 1 has no cross-module calls except dashboard reading via its own `stats_query` port.

## 6. Authentication & Authorization

- `bin/rails generate authentication` → `AdminUser` + DB-backed `Session`, bcrypt passwords.
- `AdminUser.role` enum: `superadmin`, `admin`, `viewer`.
- `AdminAuth::AccessPolicy` (PORO) is the single authority for "can this role do this action?":
  - **viewer** — read all operational pages (not the audit log), change nothing (controls hidden in UI *and* enforced in controllers via the policy).
  - **admin** — manage events, app users, master data.
  - **superadmin** — everything, plus create/deactivate admin accounts, change roles, and view the audit log.
- Login endpoint protected with Rails 8 built-in `rate_limit`.
- First superadmin is created by `db/seeds.rb`, reading credentials from ENV (never hardcoded).

### Audit log

One `admin.audit_logs` table records two kinds of entries:

1. **Auth events** — login success, login failure (attempted email), logout; with IP address, user agent, timestamp.
2. **Data changes** — every write to a Go-owned table and every admin-account change: actor, action, target record, old value → new value (JSON), timestamp.

Recording goes through the `audit_recorder` port, called from domain use cases (data changes) and the auth flow (auth events) — so it cannot be skipped by a stray controller. Entries are insert-only: no update/delete path exists in the application. A superadmin-only page lists entries with filters (admin user, action type, date range).

## 7. Data Flow (canonical example: change event status)

```
Browser (Turbo form)
  → EventsController#update_status      # web adapter: params, current_admin
    → Events::ChangeStatus.call(...)    # domain: policy check, transition check
      → event_repository.update_status  # port
        → ArEventRepository             # AR transaction + audit_logs row
  ← Result → Turbo Stream updates the row + flash message
```

Controllers contain no business logic; the domain renders nothing; adapters decide nothing.

## 8. Error Handling

- Use cases return a `Result` (`success?` / `failure?` + error message). Expected failures (invalid transition, permission denied, validation) are values, not exceptions.
- Unexpected exceptions (DB down, bugs) bubble to `rescue_from` in `ApplicationController` → 500 page + structured log via Rails logger. No `puts`-style debug output anywhere.
- Two validation layers: form objects in the web adapter (shape/format) and invariants in domain use cases (business rules).

## 9. Testing

- **Domain tests** — pure Minitest, no Rails loaded, ports stubbed with plain doubles. Fast; covers policies, state machine, use cases.
- **Adapter tests** — run against a real test database. Go-owned table structure is captured as `db/core_structure.sql` (dumped once from the dev DB, refreshed manually when the Go schema changes) and loaded into the test DB. This file is a test fixture, never a source of truth.
- **System tests** — Capybara for the critical flows: login (incl. rate limit), change event status, viewer blocked from editing, superadmin manages admin accounts.

## 10. UI & Deployment

### Corporate identity

The admin panel follows the current carbonmice web CI. Reference screenshots and the logo are committed under `docs/assets/ci/` (login, dashboard, data collection, form + `logo-carbonmice.png`). Tokens verified against `carbonmice-main-fe` source:

- **Font:** IBM Plex Sans Thai (all weights used by the main web)
- **Primary blue:** `#0065D0` (buttons, links, active states, chart primary)
- **Error red:** `#D92D20`
- **Text:** `#101828` (headings) / `#333741` (body)
- **Backgrounds:** white cards on `#F9FAFB` / `#FCFCFD`; light-blue chip badges
- **Shape:** large-radius rounded cards, soft borders, blue progress bars and donut charts (as in the reference dashboard)
- **Logo:** carbon MICE "Green Power By PEA" lockup on the login page and sidebar (layout of the login page mirrors `login-reference.png`: white form panel + sky/CO₂ image panel, full-width blue button)
- **Language:** Thai-first UI text

These map to Tailwind theme tokens (`--color-primary: #0065D0`, font family, radius scale) defined once in the app's CSS.

### Delivery

- Server-rendered ERB, Turbo for updates, Stimulus where needed. Table-first admin styling with Tailwind using the tokens above.
- Standard Rails 8 Dockerfile; a `carbonmice-admin` service added to the developer's local docker-compose setup on the existing `sit` network (compose change lives in this repo's docs/own compose file — the Go repo's compose is not modified).
- GitLab CI mirroring the team's existing pipeline conventions.

## 11. Out of Scope (Phase 1)

- SSO / carbonform integration for admin login
- Per-module granular permissions (roles are coarse-grained for now)
- English language toggle (Thai-only in phase 1)
- Managing surveys, quotations approval workflow, carbon credits, TGO registration
- Email sending from the admin panel
- Any change to the Go backend or main frontend

## 12. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Go schema changes break `Core::*` mappings | Models are thin; adapter tests against `core_structure.sql` catch drift when the fixture is refreshed; keep refresh step in README |
| Admin writes conflict with Go business logic (computed fields, cascades) | Writes restricted to whitelisted operations in use cases; computed fields read-only; audit log for forensics |
| Status transition rules drift from Go's rules | Transition table defined in one place (`Events::ChangeStatus`); documented against Go's `event_status` enum at time of writing |
| Shared DB credentials exposure | Admin app gets its own Postgres role with least privilege (full rights on `admin` schema; table-level grants on `public`) |
