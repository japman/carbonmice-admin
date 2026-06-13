# Carbonmice Admin — Plan 4a/4: Code Hardening

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the correctness/robustness gaps surfaced by the Plan 3 final review and the
roadmap's *code-level* hardening items, all verifiable locally with the test suite. Infra
work (Dockerfile, DB least-privilege roles) is split out into **Plan 4b** (deploy-time, not
locally verifiable) and CI is deferred entirely per the 2026-06-13 decision.

**Architecture:** Same hexagonal pattern as Plans 1-3. No new domain modules; this plan
hardens existing ones (`MasterData::`, `Dashboard::`) and adds one maintenance use-case.

**Scope decisions (agreed 2026-06-13):**
- CI: skipped for now (repo is on GitHub, roadmap text said GitLab — unresolved, deferred).
- Shared cache store: **Solid Cache** (DB-backed, lives in `admin` schema, no Redis/Memcached).
- Plan split: **4a = this doc** (code hardening, TDD). **4b = infra** (Dockerfile + DB roles).

**Verified facts (live code @ HEAD 7d54daf):**
- `schema_format = :sql` (`config/application.rb:39`); schema dumped to `db/structure.sql`.
  `core_structure.sql` is the Go-owned `public` schema fixture loaded in test only.
- `database.yml` → `schema_search_path: "admin,public"`. Migrations create tables in `admin`.
- Rate limiter: `SessionsController#create` uses `rate_limit to: 10, within: 3.minutes`
  (backed by `Rails.cache`). Production `cache_store` is commented out → per-process, NOT
  shared across Puma workers/hosts. Test env uses `:null_store`.
- `Audit::ListEntries.call(actor:, query:, filters:)` returns `Result.success(query.entries(**filters))`,
  gated on `:view_audit_log`. `Persistence::ArAuditLogQuery#entries(..., limit: 200)` supports `limit:`.
- `HomeController#show` reads `AuditLog.order(created_at: :desc).limit(10)` directly (the bypass
  to fix). Gate is `can?(:view_audit_log)`.
- `MasterData::UpdateEventPricingTier` / `UpdateOffsetPricingTier`: read `repo.list` → check
  `TierBounds.overlaps?` → `repo.update`. Not atomic under concurrency (review finding #4).
- `EmissionFactorsController#create/#update`: on `result.failure?` they `redirect_to … alert:`,
  dropping the 7-field form input (review finding #6). `new.html.erb` uses `scope: :emission_factor`
  with no backing object; `edit.html.erb` sets `value:` per field from `@factor`.
- `Session < ApplicationRecord` (`belongs_to :admin_user`, no expiry column). Rows accumulate.
- `AdminAuth::AccessPolicy` is the single permissions authority.

**Hard rules (unchanged):** never modify carbonmice-main-go-be; never migrate `public` tables
(only `admin`); domain files pure Ruby (no ActiveSupport/Rails constants); ALL commands via
`mise exec ruby@4.0.0 --` (plain `bin/rails` silently uses system Ruby 2.6 → "no tests ran");
libpq at /opt/homebrew/opt/libpq/bin. Suite is currently **137 runs green**.

**Batching (per repo speed policy):** batches (1+2), (3+4), (5). Commit per task; full suite at
end of each batch; reviews (spec haiku + quality sonnet) run in parallel per batch. Task 5
(Solid Cache, regenerates structure.sql) runs alone and last.

---

### Task 1: Route dashboard recent-activity through the audit port

**Why:** `HomeController#show` reads `AuditLog` directly, duplicating the audit read path that
`AuditLogsController` runs through `Audit::ListEntries` + `ArAuditLogQuery`. Single path =
one place to change gating/ordering later. (Review finding #2.)

**Files:**
- Modify: `app/controllers/home_controller.rb`
- Test: `test/controllers/dashboard_test.rb` (extend; existing assertions must stay green)

- [ ] **Step 1: failing/▲ test** — add to `dashboard_test.rb`:

```ruby
  test "recent activity comes through the audit port, newest first, capped at 10" do
    admin = login_as(:superadmin)
    12.times do |i|
      AuditLog.create!(action: "auth.login_succeeded", actor_id: admin.id,
                       actor_email: admin.email_address, created_at: i.minutes.ago)
    end
    get root_path
    assert_response :success
    rows = css_select("table:last-of-type tbody tr")
    assert_equal 10, rows.size   # ArAuditLogQuery limit honored via the port
  end
```

(Keep the existing two dashboard tests; they assert the section is visible to superadmin and
hidden from viewer — both must still pass.)

- [ ] **Step 2: run** `mise exec ruby@4.0.0 -- bin/rails test test/controllers/dashboard_test.rb` → the
  new test FAILS only if the current direct query doesn't cap at 10 (it does cap at 10, so this
  test mostly locks in behavior; if it passes immediately, that's acceptable — proceed, the
  refactor is the point).

- [ ] **Step 3: implement** — `app/controllers/home_controller.rb#show`, replace the direct read:

```ruby
    # Recent activity reuses the audited read path (gated :view_audit_log inside the use-case).
    recent = Audit::ListEntries.call(actor: current_admin,
                                     query: Persistence::ArAuditLogQuery.new,
                                     filters: { limit: 10 })
    @recent_activity = recent.success? ? recent.value : nil
```

Remove the `can?(:view_audit_log) ? AuditLog.order(...) : nil` line. The use-case's internal
`:view_audit_log` gate now decides visibility (viewer → failure → nil), preserving behavior.

- [ ] **Step 4: run** dashboard_test (3 runs) + full `home_controller_test` green.
- [ ] **Step 5: commit** — `refactor: dashboard recent-activity reads through the audit port`

---

### Task 2: Preserve emission-factor form input on validation error

**Why:** A duplicate-identifier or bad-value error on the 7-field EF form currently redirects and
wipes everything the user typed. Re-render the form with the submitted values instead.
(Review finding #6.)

**Files:**
- Modify: `app/controllers/emission_factors_controller.rb`, `app/views/emission_factors/new.html.erb`,
  `app/views/emission_factors/edit.html.erb`
- Test: `test/controllers/emission_factors_controller_test.rb` (extend)

- [ ] **Step 1: failing test** — add:

```ruby
  test "create error re-renders new with submitted values and no redirect" do
    login(@superadmin)
    create_core_emission_factor!(identifier: "ef_dup")   # seed an existing identifier
    category_id = Core::CarbonCategory.kept.first.id
    assert_no_difference -> { Core::EmissionFactor.kept.count } do
      post emission_factors_path, params: { emission_factor: {
        identifier: "ef_dup", name: "ชื่อที่พิมพ์ไว้", source: "TGO",
        value_per_unit: "2.5", unit_title: "kgCO2e/kg", carbon_category_id: category_id } }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='emission_factor[name]'][value='ชื่อที่พิมพ์ไว้']"
    assert_select "input[name='emission_factor[identifier]'][value='ef_dup']"
  end

  test "update error re-renders edit with submitted value and no redirect" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_edit_err", value: 1.5)
    patch emission_factor_path(f.id), params: { emission_factor: { value_per_unit: "-3" } }
    assert_response :unprocessable_entity
    assert_select "input[name='emission_factor[value_per_unit]'][value='-3']"
    assert_equal 1.5, f.reload.value_per_unit.to_f
  end
```

- [ ] **Step 2: run** → FAIL (currently redirects).

- [ ] **Step 3: implement** — controller failure branches re-render instead of redirect:

```ruby
  def create
    result = MasterData::CreateEmissionFactor.call(actor: current_admin, repo: repo, audit: audit,
                                                   attrs: factor_params.to_h.symbolize_keys)
    if result.success?
      redirect_to emission_factors_path, notice: "สร้างค่า EF แล้ว"
    else
      @factor = OpenStruct.new(factor_params.to_h)
      @categories = Core::CarbonCategory.kept.order(:name_eng)
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
  end

  def update
    result = MasterData::UpdateEmissionFactor.call(actor: current_admin, id: params[:id],
                                                   repo: repo, audit: audit,
                                                   attrs: update_params.to_h.symbolize_keys)
    if result.success?
      redirect_to emission_factors_path, notice: "บันทึกการแก้ไขแล้ว"
    else
      @factor = repo.find(params[:id])
      @factor.assign_attributes(update_params.to_h)   # show what the user typed, not the saved value
      flash.now[:alert] = result.error
      render :edit, status: :unprocessable_entity
    end
  rescue Ports::NotFound
    redirect_to emission_factors_path, alert: "ไม่พบค่า EF"
  end
```

Add `require "ostruct"` at the top of the controller (OpenStruct is no longer default-required
in Ruby 3.5+/4.0). `new` action already sets `@categories`; make `new.html.erb` read field
values from `@factor` when present so both the fresh and re-render paths work:

In `new.html.erb`, give each field a value fallback, e.g.:
```erb
<%= f.text_field :identifier, value: @factor&.identifier, required: true, maxlength: 255,
      pattern: "[a-z0-9_.]+", class: "..." %>
```
Apply the same `value: @factor&.<attr>` to name, description, source, value_per_unit, unit_title,
and `selected: @factor&.carbon_category_id` on the category select. `@factor` is nil on the
normal `new` GET (blank form), populated on re-render. `edit.html.erb` already binds to `@factor`
(an AR record on the error path now), so verify its `value:` reads still work and the disabled
identifier field still shows `@factor.identifier`.

- [ ] **Step 4: run** target tests (new 2 + existing EF controller tests) green. The existing
  "creates, edits and deletes" and "viewer" tests assert redirects on the SUCCESS/denied paths —
  those are unchanged (only the failure path changed), so they stay green. Confirm.
- [ ] **Step 5: commit** — `feat: re-render emission-factor form with input preserved on error`

---

### Task 3: Serialize concurrent tier updates with an advisory lock

**Why:** `UpdateEventPricingTier`/`UpdateOffsetPricingTier` do read-check-write with no lock; two
admins could commit overlapping ranges (no DB exclusion constraint backs the invariant).
(Review finding #4.) Take a Postgres transaction-scoped advisory lock so overlapping-range
edits to the same table serialize.

**Design:** The domain stays pure — it calls a new port method `advisory_lock!` FIRST (before
`repo.list`). The AR adapters implement it as `pg_advisory_xact_lock` (released at transaction
commit). The controller opens the transaction around the use-case call (precedent:
`SessionsController#create` already wraps work in `ApplicationRecord.transaction`). Fakes get a
no-op `advisory_lock!`.

**Files:**
- Modify: `app/domain/ports/pricing_tier_repositories.rb` (document the new method),
  `app/domain/master_data/update_event_pricing_tier.rb`,
  `app/domain/master_data/update_offset_pricing_tier.rb`,
  `app/adapters/persistence/ar_event_pricing_tier_repository.rb`,
  `app/adapters/persistence/ar_offset_pricing_tier_repository.rb`,
  `app/controllers/pricing_tiers_controller.rb`
- Test: `test/domain/master_data/pricing_tiers_test.rb` (extend the fake + assert lock taken
  before the overlap read), `test/adapters/ar_pricing_tier_repositories_test.rb` (assert
  `advisory_lock!` runs without error inside a transaction)

- [ ] **Step 1: failing test** — in the domain test, give `FakeTierRepo` a recorder:

```ruby
class FakeTierRepo
  attr_reader :rows, :events
  def initialize(rows) = (@rows = rows; @events = [])
  def advisory_lock! = @events << :locked
  def find(id) = (@events << :find; @rows.fetch(id) { raise Ports::NotFound })
  def list(source_id: nil) = (@events << :list; ...existing...)
  # update unchanged
end
```
Then assert ordering in an existing update test: `assert_equal :locked, repo.events.first`
(lock acquired before any read).

For the adapter test add:
```ruby
  test "advisory_lock! acquires a xact lock without error" do
    repo = Persistence::ArEventPricingTierRepository.new
    ActiveRecord::Base.transaction { assert_nil repo.advisory_lock! }
  end
```

- [ ] **Step 2: run** → FAIL (`advisory_lock!` undefined).

- [ ] **Step 3: implement**

Port doc (`pricing_tier_repositories.rb`) — add to the contract comment:
```
  #   advisory_lock!  -> acquires a transaction-scoped lock serializing range edits
  #                      (no-op outside a transaction in fakes); call FIRST in update use-cases
```

Both use-cases — add as the first line inside `call`, right after the access-policy guard:
```ruby
      repo.advisory_lock!
```

`ar_event_pricing_tier_repository.rb`:
```ruby
    # Serializes concurrent range edits. Keyed by a stable constant per table so only
    # writers to the SAME table contend. xact-scoped: released on COMMIT/ROLLBACK.
    def advisory_lock!
      Core::EventPricingTier.connection.execute(
        "SELECT pg_advisory_xact_lock(#{LOCK_KEY})"
      )
      nil
    end
```
with `LOCK_KEY = 0x6576656e74` (or any fixed bigint literal; comment it as "event_pricing_tiers").
`ar_offset_pricing_tier_repository.rb` mirrors it with a DIFFERENT constant (e.g. `0x6f6666736574`).

`pricing_tiers_controller.rb` — wrap both update actions' domain calls:
```ruby
  def update_event
    result = ActiveRecord::Base.transaction do
      MasterData::UpdateEventPricingTier.call(actor: current_admin, id: params[:id],
        attrs: tier_params(:min_participants, :max_participants, :price_per_person),
        repo: event_repo, audit: audit)
    end
    # ...unchanged success/failure redirects...
  end
```
(same for `update_offset`). The lock is held for the whole read-check-write, released at commit.

- [ ] **Step 4: run** domain test + adapter test + `pricing_tiers_controller_test` green.
- [ ] **Step 5: commit** — `fix: serialize tier-range updates with a transaction advisory lock`

---

### Task 4: Session cleanup maintenance task

**Why:** `sessions` rows accumulate forever (no expiry column, no sweep). Roadmap item.

**Design:** A `Session.older_than(age)` scope + a rake task `admin:purge_sessions` that deletes
sessions whose `updated_at` is older than a configurable age (default 30 days). Kept simple and
testable; not wired to a scheduler here (that's deploy-time / Plan 4b).

**Files:**
- Modify: `app/models/session.rb`
- Create: `lib/tasks/sessions.rake`
- Test: `test/models/session_test.rb`, `test/tasks/purge_sessions_test.rb`

- [ ] **Step 1: confirm columns** — verify `sessions` has `updated_at` (from
  `create_admin_auth_tables` `t.timestamps`). If only `created_at` exists, base the scope on
  that and note it. (Implementer: check the migration / `\d admin.sessions` before writing.)

- [ ] **Step 2: failing test** — `test/models/session_test.rb`:

```ruby
require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "older_than selects only sessions stale past the cutoff" do
    admin = AdminUser.create!(email_address: "s@pea.co.th", password: "password-for-tests",
                              name: "ส", role: :admin)
    old = Session.create!(admin_user: admin, ip_address: "1.1.1.1", user_agent: "x",
                          updated_at: 40.days.ago)
    fresh = Session.create!(admin_user: admin, ip_address: "2.2.2.2", user_agent: "y")
    stale = Session.older_than(30.days)
    assert_includes stale, old
    refute_includes stale, fresh
  end
end
```

- [ ] **Step 3: implement** — `session.rb`:
```ruby
class Session < ApplicationRecord
  belongs_to :admin_user

  # Sessions never expire on their own; the admin:purge_sessions task sweeps stale rows.
  scope :older_than, ->(age) { where(updated_at: ..age.ago) }
end
```

`lib/tasks/sessions.rake`:
```ruby
namespace :admin do
  desc "Delete login sessions not updated within ADMIN_SESSION_TTL_DAYS (default 30)"
  task purge_sessions: :environment do
    days = Integer(ENV.fetch("ADMIN_SESSION_TTL_DAYS", "30"))
    deleted = Session.older_than(days.days).delete_all
    puts "Purged #{deleted} stale session(s) older than #{days} days."
  end
end
```

- [ ] **Step 4: rake test** — `test/tasks/purge_sessions_test.rb`:
```ruby
require "test_helper"
require "rake"

class PurgeSessionsTest < ActiveSupport::TestCase
  setup do
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake.application.rake_require("tasks/sessions", [Rails.root.join("lib").to_s])
    Rake::Task.define_task(:environment)
  end

  test "admin:purge_sessions deletes stale rows only" do
    admin = AdminUser.create!(email_address: "p@pea.co.th", password: "password-for-tests",
                              name: "พี", role: :admin)
    Session.create!(admin_user: admin, ip_address: "1.1.1.1", user_agent: "x", updated_at: 40.days.ago)
    keep = Session.create!(admin_user: admin, ip_address: "2.2.2.2", user_agent: "y")
    @rake["admin:purge_sessions"].invoke
    assert Session.exists?(keep.id)
    assert_equal 1, Session.count
  end
end
```

- [ ] **Step 5: run** both tests green; full suite.
- [ ] **Step 6: commit** — `feat: admin:purge_sessions task to sweep stale login sessions`

---

### Task 5: Shared cache store via Solid Cache (rate limiter)

**Why:** The login rate limiter uses `Rails.cache`; with no shared store, each Puma worker/host
counts independently, so the real limit is `10 × workers`. Solid Cache (DB-backed) gives a
shared store with no new infrastructure — its table lives in the `admin` schema. Roadmap item.

**Run alone (regenerates `db/structure.sql`).**

**Files:**
- Modify: `Gemfile`, `Gemfile.lock`, `config/environments/production.rb`, `db/structure.sql`
- Create: `config/cache.yml` (or `config/solid_cache.yml` per installer), `db/migrate/<ts>_create_solid_cache_entries.rb`
- Test: `test/integration/cache_store_test.rb`

- [ ] **Step 1: add gem + install**
```bash
mise exec ruby@4.0.0 -- bundle add solid_cache
mise exec ruby@4.0.0 -- bin/rails solid_cache:install
```
The installer adds a migration, a config file, and sets `config.cache_store = :solid_cache_store`
in production. **Pin it to the primary connection** (single-DB app): in the generated config,
set the store to use the primary database (`database: primary` / remove any separate `cache` db
wiring) so the `solid_cache_entries` table is created in the `admin` schema by the normal
migration — DO NOT add a second database to `database.yml`, and DO NOT let the migration target
`public`.

- [ ] **Step 2: migrate** — `mise exec ruby@4.0.0 -- bin/rails db:migrate`. Confirm
  `solid_cache_entries` lands in `admin` (search_path) and `db/structure.sql` is regenerated with
  it under `admin`. Verify the `public` (Go) section of structure.sql is UNCHANGED
  (`git diff db/structure.sql` should only add the admin-schema cache table + schema_migrations row).

- [ ] **Step 3: test** — `test/integration/cache_store_test.rb` (exercises the store directly;
  test env can point at solid_cache for this test or assert the production config resolves):
```ruby
require "test_helper"

class CacheStoreTest < ActiveSupport::TestCase
  test "solid cache round-trips a value through the database store" do
    store = ActiveSupport::Cache.lookup_store(:solid_cache_store)
    store.write("plan4a:probe", "ok")
    assert_equal "ok", store.read("plan4a:probe")
  end

  test "production is configured to use the shared solid cache store" do
    config = Rails.application.config_for(:cache) rescue nil
    assert defined?(SolidCache), "solid_cache gem must be loaded"
  end
end
```
(Implementer: adapt the second assertion to however the installer wired it — the durable check
is that production `cache_store` resolves to `:solid_cache_store`, not `:memory_store`.)

- [ ] **Step 4: run** the cache test + FULL suite (`mise exec ruby@4.0.0 -- bin/rails test`,
  expect 137 + new runs, 0 failures) + `bin/rubocop` + `bundle exec brakeman -q`.
- [ ] **Step 5: commit** — `feat: shared Solid Cache store so the login rate limiter spans workers`

---

### Final verification (end of Task 5 / whole plan)

```bash
mise exec ruby@4.0.0 -- bin/rails test            # all green
mise exec ruby@4.0.0 -- bin/rails test:system     # 4 runs green
for f in test/domain/**/*_test.rb; do mise exec ruby@4.0.0 -- ruby -Itest "$f"; done
mise exec ruby@4.0.0 -- bin/rubocop               # 0 offenses
mise exec ruby@4.0.0 -- bundle exec brakeman -q   # exit 0
```

Update `README.md`: add the `admin:purge_sessions` task and the Solid Cache note; mark Plan 4a done.

---

## After this plan

**Plan 4b (infra, deploy-time):** Rails Dockerfile (multi-stage, thruster) + `.dockerignore`;
dedicated DB role (full on `admin`, table grants on `public`) + `REVOKE UPDATE/DELETE` on
`admin.audit_logs`; schedule `admin:purge_sessions` (cron/whenever/deploy scheduler); CI provider
decision (GitHub Actions vs GitLab) once the deploy target is known. These are not locally
verifiable beyond build-time and are tracked in a separate doc.

**Deferred:** re-enable `parallelize(workers: :number_of_processors)` once the pg gem fixes the
Ruby 4.0 fork segfault; tier create/delete UI if operationally needed.
