# Audit log — capture request IP / User-Agent for all actions

> Feature 2 of 3 in the current batch. Locally verifiable. Cross-cutting but mechanical.
> No domain-signature change, no Go change, no migration. Ships before the `v0.0.1` tag.

## Problem

In the audit-log page, `auth.*` rows show an IP (e.g. `172.22.0.1`) but every other action
— `events.status_changed`, `master_data.*`, `app_users.*`, `admin_users.*` — shows a blank
IP column.

## Root cause

`Persistence::ArAuditRecorder#record` already accepts `ip:` and `user_agent:`. The **auth**
controllers (`sessions_controller`, `passwords_controller`, and the `Authentication`
concern) pass `ip: request.remote_ip` explicitly, so their rows get an IP. But the **20
domain use-cases** (`app/domain/**`) call `audit.record(action:, actor:, target:, changes:)`
with **no** `ip:` — by design, because the domain layer is pure Ruby and has no access to
the web `request`. So `ip_address`/`user_agent` are `nil` for everything that flows through a
use-case.

This is an architectural gap, not a per-call bug: the controller is the only layer that can
see `request`, but each controller hands the use-case a bare `ArAuditRecorder.new`.

## Design — Option C: bake request context into the recorder at the controller boundary

Keep the domain layer untouched (it must stay Rails-free, and its `audit.record(...)` calls
stay exactly as they are). Move the request context into the **adapter** the controller
constructs:

1. `Persistence::ArAuditRecorder.new(ip:, user_agent:)` stores the two values; `record`
   defaults its `ip:`/`user_agent:` params to the stored values. An explicit `ip:` passed to
   `record` still wins (so the auth controllers keep working unchanged).
2. A single shared `audit` helper on `ApplicationController` builds the recorder **with**
   `request.remote_ip` / `request.user_agent` — the one place where `request` is in scope.
3. The 8 per-controller `def audit = Persistence::ArAuditRecorder.new` definitions are
   removed; those controllers inherit the request-aware helper. The use-cases they call now
   record with the request's IP/UA automatically — no use-case signature changes.

This is the minimal change that closes the gap for **all** controller-driven audited actions
at once, without leaking `request` into the domain.

## Changes

### `app/adapters/persistence/ar_audit_recorder.rb`
- Add `def initialize(ip: nil, user_agent: nil)` storing `@ip` / `@user_agent`.
- Change `record` so its `ip:`/`user_agent:` keyword defaults are `@ip` / `@user_agent`
  (was `nil`). Behaviour with an explicit `ip:`/`user_agent:` argument is unchanged.

### `app/controllers/application_controller.rb`
- Add a private helper:
  `def audit = Persistence::ArAuditRecorder.new(ip: request.remote_ip, user_agent: request.user_agent)`.

### Remove the now-redundant per-controller helper
Delete `def audit = Persistence::ArAuditRecorder.new` from these 8 controllers (they inherit
the shared one):
`categories_controller`, `events_controller`, `carbon_credits_controller`,
`pricing_tiers_controller`, `carbon_offset_sources_controller`, `admin_users_controller`,
`emission_factors_controller`, `app_users_controller`.

### Auth controllers — leave unchanged
`sessions_controller` (`def audit_recorder = ArAuditRecorder.new`, `record(..., ip:
request.remote_ip)`) and `passwords_controller` (inline `ArAuditRecorder.new.record(...,
ip: request.remote_ip)`) already pass IP explicitly and keep working (explicit arg overrides
the new constructor default). Not touched, to keep the change minimal.

### Tests
- **`test/adapters/ar_audit_recorder_test.rb`** — add: (a) a recorder built with
  `ArAuditRecorder.new(ip: "9.9.9.9", user_agent: "ua")` and `record(...)` **without**
  ip/user_agent persists `ip_address == "9.9.9.9"` / `user_agent == "ua"`; (b) an explicit
  `record(..., ip: "1.2.3.4")` **overrides** the constructor default.
- **Integration test** — add one test to `test/controllers/events_controller_test.rb`: as a
  logged-in superadmin, `patch status_event_path(event)` with a valid transition (e.g. a
  "collecting" event → `to: "in_progress"`), then assert the created
  `AuditLog.where(action: "events.status_changed").last` has `ip_address == "127.0.0.1"`
  (the IP of integration-test requests). The PATCH does not render the dropdown, so no
  `event_statuses` seeding is needed. This proves the gap is closed end-to-end for
  controller → use-case → recorder.

## Out of scope
- Any change to `app/domain/**` (use-case signatures and their `audit.record(...)` calls stay
  identical).
- Backfilling IP onto historical audit rows.
- Recording IP for genuinely request-less audits (e.g. background jobs) — `nil` is correct
  there.
- The Go backend, DB schema, migrations.

## Verification
1. `mise exec ruby@4.0.0 -- bin/rails test test/adapters/ar_audit_recorder_test.rb` and the
   chosen controller test → green.
2. Batch gate: full `bin/rails test`, `bin/rails test:system`, `bin/rubocop`,
   `bundle exec brakeman -q` → all clean.
3. Manual smoke (docker compose up): change an event status / edit master data, open
   บันทึกการใช้งาน → the new row now shows an IP in the IP column.
