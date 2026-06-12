# Carbonmice Admin — Plan 2/3: Core Read Layer, Events & App Users

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins can search/inspect events, correct event statuses (audited, mirroring the Go backend's transition rules), edit safe descriptive fields, and manage app users (role + event quota) — all over the Go backend's `public` tables via read models and whitelisted, audited writes.

**Architecture:** Same hexagonal pattern as Plan 1: pure-PORO use cases + ports in `app/domain/`, AR adapters in `app/adapters/persistence/`, thin controllers. NEW: `Core::` models map Go-owned `public` tables (explicit `self.table_name = "public.…"`, no migrations, no callbacks). Reads go through query methods on repository ports; writes go ONLY through use cases that audit every change and stamp `updated_by = "carbonmice-admin:<email>"` so the Go side sees who changed what.

**Tech Stack:** unchanged (Rails 8.1.3 / Ruby 4.0 via mise, shared Postgres, Minitest). Test DB gets a structure-only snapshot of the `public` schema (`db/core_structure.sql`).

**Spec:** `docs/superpowers/specs/2026-06-12-admin-panel-design.md` — Plan 3 (master data CRUD, dashboard, Capybara system tests, Dockerfile + GitLab CI, password change, session cleanup, audit REVOKE) follows after this plan.

**Hard rules for every task:**
- NEVER modify anything under `carbonmice-main-go-be` (read-only; running its docker compose is allowed).
- NEVER migrate/alter `public` tables. Plan-2 writes UPDATE existing rows only — zero INSERTs into `public` outside the test database.
- Domain files stay pure Ruby (no ActiveSupport — no `.present?`/`.blank?` in `app/domain/`).
- Run commands via `mise exec ruby@4.0.0 --` when plain `ruby -v` isn't 4.0.x; psql/pg_dump need `/opt/homebrew/opt/libpq/bin` on PATH. Dev DB: `postgres://postgres:password@localhost:5432/carbon-mice`.

**Verified Go-schema facts used throughout (from live DB + Go source):**
- `public.events`: uuid PK, `name_thai`/`name_eng`, `area_name`, `province`, `event_status` varchar (a STRING, not FK), `payment_status` (CHECK pending_payment/paid), `created_by` varchar NOT NULL (user raw_id), `event_template_id` uuid NOT NULL FK, `deleted_at` soft delete, computed flags like `quota_deducted` (never write).
- `public.event_statuses`: 13 rows, `name_eng`/`name_thai`/`running_order` — display catalog only.
- Status transitions: Go `ValidateStatus` (internal/model/event.go:444) — mostly backward corrections; forward flow lives in `EscalateEventStatus` (email + quota side effects). The admin table mirrors ValidateStatus minus the `pending_email_confirm` and `quotation` targets.
- `public.users`: uuid PK, `raw_id` NOT NULL, `email`, `display_name`, `role` varchar (values: user / admin / super_admin / visitor), `event_quota` int default 0, `is_package_user` bool, `deleted_at`.
- `public.carbon_emissions`: `event_id`/`carbon_category_id`/`unit_id` uuid NOT NULL FKs, `pre_event_emission` NOT NULL numeric, `post_event_emission` numeric.
- Test-factory FK chains: events ← event_templates(name, license_fee, created_by, event_type_id NOT NULL) ← event_types(name, created_by); carbon_categories ← carbon_scopes(name CHECK IN scope_1/2/3, created_by).

---

### Task 1: `db/core_structure.sql` fixture + test bootstrap + Core factories

**Files:**
- Create: `db/core_structure.sql` (generated), `test/support/core_factories.rb`
- Modify: `test/test_helper.rb`
- Test: `test/models/core_structure_test.rb`

- [ ] **Step 1: Write the failing smoke test** — `test/models/core_structure_test.rb`

```ruby
require "test_helper"

class CoreStructureTest < ActiveSupport::TestCase
  test "Go-owned public tables exist in the test database" do
    %w[events users event_statuses carbon_emissions carbon_categories units].each do |table|
      assert ActiveRecord::Base.connection.data_source_exists?("public.#{table}"),
             "expected public.#{table} to exist (core_structure.sql not loaded?)"
    end
  end

  test "core factories build a full event chain" do
    event = create_core_event!(name_thai: "งานทดสอบ", status: "draft")
    assert_equal "งานทดสอบ", event.name_thai
    assert_equal "draft", event.event_status

    user = create_core_user!(email: "u@example.com", role: "user", quota: 2)
    assert_equal 2, user.event_quota
  end
end
```

- [ ] **Step 2: Run it** — `bin/rails test test/models/core_structure_test.rb` → FAIL (`public.events` missing / `create_core_event!` undefined).

- [ ] **Step 3: Dump the public schema structure** (snapshot fixture — never a source of truth):

```bash
cd /Users/japman/Documents/Backup/Project/PEA/carbonmice/carbonmice-admin
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
{ echo "-- TEST FIXTURE: structure-only snapshot of the Go backend's public schema."
  echo "-- Regenerate with the command in README when the Go schema changes. Never edit by hand."
  pg_dump "postgres://postgres:password@localhost:5432/carbon-mice" \
    --schema=public --schema-only --no-owner --no-privileges \
  | grep -v '^\\' ; } > db/core_structure.sql
```

The `grep -v '^\\'` strips psql meta-commands (`\restrict` etc.) that `raw_connection.exec` cannot run. If the dump contains a `CREATE SCHEMA public;` line, delete that line too (the schema already exists in the test DB).

- [ ] **Step 4: Bootstrap loading in `test/test_helper.rb`** — after `require "rails/test_help"`, before the `module ActiveSupport` block:

```ruby
# Load the Go backend's table structure (public schema) into the test DB once.
# db/core_structure.sql is a fixture dumped from the dev DB — see README.
connection = ActiveRecord::Base.connection
unless connection.data_source_exists?("public.events")
  connection.raw_connection.exec(File.read(File.expand_path("../db/core_structure.sql", __dir__)))
  # pg_dump pins search_path to '' for the session — restore ours.
  connection.execute("SET search_path TO admin, public")
end

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }
```

And inside `class TestCase`, add `include CoreFactories`.

- [ ] **Step 5: Create `test/support/core_factories.rb`**

```ruby
# Builders for rows in the Go-owned public schema (TEST DATABASE ONLY).
# Raw SQL on purpose: the app has no write path that INSERTs into public,
# and we keep it that way — these helpers must never leak into app code.
module CoreFactories
  def create_core_event!(name_thai: "งานทดสอบ", name_eng: "Test Event", status: "draft",
                         area_name: nil, province: nil, created_by: "test-user")
    conn = ActiveRecord::Base.connection
    type_id = conn.select_value(
      "INSERT INTO public.event_types (name, created_by) VALUES ('ทดสอบ', 'test') RETURNING id"
    )
    template_id = conn.select_value(sanitize_sql(
      "INSERT INTO public.event_templates (name, license_fee, created_by, event_type_id)
       VALUES ('เทมเพลตทดสอบ', 0, 'test', ?) RETURNING id", type_id
    ))
    event_id = conn.select_value(sanitize_sql(
      "INSERT INTO public.events (name_thai, name_eng, event_status, area_name, province, created_by, event_template_id)
       VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id",
      name_thai, name_eng, status, area_name, province, created_by, template_id
    ))
    Core::Event.find(event_id)
  end

  def create_core_user!(email:, role: "user", quota: 0, display_name: "ผู้ใช้ทดสอบ",
                        package: false, raw_id: SecureRandom.uuid)
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.users (raw_id, email, role, event_quota, is_package_user, display_name, created_by)
       VALUES (?, ?, ?, ?, ?, ?, 'test') RETURNING id",
      raw_id, email, role, quota, package, display_name
    ))
    Core::User.find(id)
  end

  def create_core_emission!(event_id:, category_eng: "travel", category_thai: "การเดินทาง", pre: 10.5, post: nil)
    conn = ActiveRecord::Base.connection
    scope_id = conn.select_value(
      "INSERT INTO public.carbon_scopes (name, created_by) VALUES ('scope_1', 'test') RETURNING id"
    )
    category_id = conn.select_value(sanitize_sql(
      "INSERT INTO public.carbon_categories (name_thai, name_eng, carbon_scope_id, created_by)
       VALUES (?, ?, ?, 'test') RETURNING id", category_thai, category_eng, scope_id
    ))
    unit_id = conn.select_value(
      "INSERT INTO public.units (code, multiplier, created_by) VALUES ('kg', 1, 'test') RETURNING id"
    )
    conn.select_value(sanitize_sql(
      "INSERT INTO public.carbon_emissions (event_id, carbon_category_id, unit_id, pre_event_emission, post_event_emission, created_by)
       VALUES (?, ?, ?, ?, ?, 'test') RETURNING id",
      event_id, category_id, unit_id, pre, post
    ))
  end

  private

    def sanitize_sql(sql, *binds)
      ActiveRecord::Base.sanitize_sql_array([sql, *binds])
    end
end
```

SEQUENCING NOTE: the factories return `Core::Event`/`Core::User`, which Task 2 defines. In THIS task the smoke test's first case goes green (tables exist) while the factory case stays red with `uninitialized constant Core` — that is the expected intermediate state, called out in the commit message below. Task 2 turns it green.

- [ ] **Step 6: Run** — `bin/rails test test/models/core_structure_test.rb`
Expected: test 1 PASS (tables exist), test 2 ERROR (`uninitialized constant Core...`) — that constant arrives in Task 2.
Also verify the rest of the suite is untouched: `bin/rails test` → 52 existing tests still pass, 1 error (the factory test).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "test: load Go public-schema snapshot into test DB with core factories

core_structure_test's factory case stays red until Core models land (next commit)."
```

---

### Task 2: `Core::` read models

**Files:**
- Create: `app/models/core/base.rb`, `app/models/core/event.rb`, `app/models/core/user.rb`, `app/models/core/event_status.rb`, `app/models/core/carbon_emission.rb`, `app/models/core/carbon_category.rb`, `app/models/core/unit.rb`
- Test: `test/models/core_models_test.rb`

- [ ] **Step 1: Write the failing test** — `test/models/core_models_test.rb`

```ruby
require "test_helper"

class CoreModelsTest < ActiveSupport::TestCase
  test "Core::Event maps public.events and scopes out soft-deleted rows" do
    kept = create_core_event!(name_thai: "ยังอยู่")
    gone = create_core_event!(name_thai: "ถูกลบ")
    ActiveRecord::Base.connection.execute(
      "UPDATE public.events SET deleted_at = now() WHERE id = '#{gone.id}'"
    )
    names = Core::Event.kept.pluck(:name_thai)
    assert_includes names, "ยังอยู่"
    refute_includes names, "ถูกลบ"
  end

  test "Core::User maps public.users" do
    create_core_user!(email: "map@example.com", role: "admin", quota: 3)
    u = Core::User.kept.find_by(email: "map@example.com")
    assert_equal "admin", u.role
    assert_equal 3, u.event_quota
  end

  test "Core::CarbonEmission joins category and unit" do
    event = create_core_event!
    create_core_emission!(event_id: event.id, category_thai: "การเดินทาง", pre: 12.5)
    e = Core::CarbonEmission.where(event_id: event.id).includes(:carbon_category, :unit).first
    assert_equal "การเดินทาง", e.carbon_category.name_thai
    assert_equal "kg", e.unit.code
    assert_equal 12.5, e.pre_event_emission.to_f
  end
end
```

- [ ] **Step 2: Run** — FAIL (`uninitialized constant Core`).

- [ ] **Step 3: Implement**

`app/models/core/base.rb`:

```ruby
module Core
  # Read models over tables owned by the Go backend. Rules (spec §4):
  # explicit table_name pinned to public, no migrations, no callbacks,
  # no business logic. Writes happen ONLY in persistence adapters invoked
  # by audited domain use cases — never from controllers or views.
  class Base < ApplicationRecord
    self.abstract_class = true

    scope :kept, -> { where(deleted_at: nil) }
  end
end
```

`app/models/core/event.rb`:

```ruby
module Core
  class Event < Base
    self.table_name = "public.events"

    has_many :carbon_emissions, class_name: "Core::CarbonEmission",
             foreign_key: :event_id, inverse_of: false
  end
end
```

`app/models/core/user.rb`:

```ruby
module Core
  class User < Base
    self.table_name = "public.users"
  end
end
```

`app/models/core/event_status.rb`:

```ruby
module Core
  # Display catalog (13 rows seeded by the Go backend). events.event_status
  # stores the name_eng STRING — this table is for labels/ordering only.
  class EventStatus < Base
    self.table_name = "public.event_statuses"

    scope :ordered, -> { kept.order(:running_order) }
  end
end
```

`app/models/core/carbon_emission.rb`:

```ruby
module Core
  class CarbonEmission < Base
    self.table_name = "public.carbon_emissions"

    belongs_to :carbon_category, class_name: "Core::CarbonCategory"
    belongs_to :unit, class_name: "Core::Unit"
  end
end
```

`app/models/core/carbon_category.rb`:

```ruby
module Core
  class CarbonCategory < Base
    self.table_name = "public.carbon_categories"
  end
end
```

`app/models/core/unit.rb`:

```ruby
module Core
  class Unit < Base
    self.table_name = "public.units"
  end
end
```

- [ ] **Step 4: Run** — `bin/rails test test/models/core_models_test.rb test/models/core_structure_test.rb` → PASS (5 runs). Full suite green.

- [ ] **Step 5: Commit** — `feat: Core read models over Go-owned public tables`

---

### Task 3: `Events::ChangeStatus` — pure domain, TDD

**Files:**
- Create: `app/domain/audit_identity.rb`, `app/domain/events/change_status.rb`, `app/domain/ports/event_repository.rb`
- Test: `test/domain/events/change_status_test.rb`

- [ ] **Step 1: Write the failing test** — `test/domain/events/change_status_test.rb`

```ruby
require_relative "../../domain_helper"

FakeEvent = Struct.new(:id, :name_thai, :event_status, :updated_by, keyword_init: true)

class FakeEventRepo
  attr_reader :rows
  def initialize(rows = {}) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def update_status(id, to:, updated_by:)
    row = find(id)
    row.event_status = to
    row.updated_by = updated_by
    row
  end
end

class FakeEventAudit
  attr_reader :entries
  def initialize = @entries = []
  def record(**entry) = @entries << entry
end

class ChangeStatusTest < Minitest::Test
  def setup
    @audit = FakeEventAudit.new
    @superadmin = Struct.new(:id, :role, :email_address)
                        .new(1, "superadmin", "sa@pea.co.th")
    @viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
  end

  def repo_with(status)
    FakeEventRepo.new({ "e1" => FakeEvent.new(id: "e1", name_thai: "งาน", event_status: status) })
  end

  def test_valid_transition_updates_and_audits
    repo = repo_with("collecting")
    result = Events::ChangeStatus.call(actor: @superadmin, id: "e1", to: "in_progress",
                                       repo: repo, audit: @audit)
    assert result.success?
    assert_equal "in_progress", repo.find("e1").event_status
    assert_equal "carbonmice-admin:sa@pea.co.th", repo.find("e1").updated_by
    entry = @audit.entries.last
    assert_equal "events.status_changed", entry[:action]
    assert_equal({ "event_status" => { "from" => "collecting", "to" => "in_progress" } }, entry[:changes])
  end

  def test_invalid_transition_is_rejected
    repo = repo_with("draft")
    result = Events::ChangeStatus.call(actor: @superadmin, id: "e1", to: "done",
                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_equal "draft", repo.find("e1").event_status
    assert_empty @audit.entries
  end

  def test_side_effect_transition_is_not_offered
    # draft→pending_email_confirm triggers email + quota deduction in Go —
    # the admin app must refuse it even though Go's ValidateStatus allows it.
    repo = repo_with("draft")
    result = Events::ChangeStatus.call(actor: @superadmin, id: "e1", to: "pending_email_confirm",
                                       repo: repo, audit: @audit)
    assert result.failure?
  end

  def test_unknown_target_status_is_rejected
    result = Events::ChangeStatus.call(actor: @superadmin, id: "e1", to: "ascended",
                                       repo: repo_with("draft"), audit: @audit)
    assert result.failure?
  end

  def test_viewer_is_denied
    result = Events::ChangeStatus.call(actor: @viewer, id: "e1", to: "in_progress",
                                       repo: repo_with("collecting"), audit: @audit)
    assert result.failure?
    assert_empty @audit.entries
  end

  def test_unknown_event_fails_gracefully
    result = Events::ChangeStatus.call(actor: @superadmin, id: "nope", to: "in_progress",
                                       repo: FakeEventRepo.new, audit: @audit)
    assert result.failure?
    assert_equal "ไม่พบอีเว้นท์", result.error
  end

  def test_transition_table_mirrors_go_validate_status
    # Pinned against carbonmice-main-go-be/internal/model/event.go:444
    # (ValidateStatus). If the Go side changes, update BOTH (and re-verify
    # the two intentionally omitted targets, see TRANSITIONS comment).
    expected = {
      "draft"            => ["draft", "pending_email_confirm", ""],
      "email_confirmed"  => ["survey_published"],
      "quotation_review" => ["quotation"],
      "survey_published" => ["collecting"],
      "collecting"       => ["quotation_review", "reject"],
      "in_progress"      => ["collecting"],
      "done"             => ["in_progress"],
      "complete"         => ["done", "collecting"],
      "carbon_credit"    => ["complete"],
      "offset_carbon"    => ["complete", "carbon_credit"],
      "send_data"        => ["complete", "offset_carbon"],
      "reject"           => ["in_progress"]
    }
    assert_equal expected, Events::ChangeStatus::TRANSITIONS
    refute Events::ChangeStatus::TRANSITIONS.key?("pending_email_confirm")
    refute Events::ChangeStatus::TRANSITIONS.key?("quotation")
  end
end
```

- [ ] **Step 2: Run** — `ruby -Itest test/domain/events/change_status_test.rb` → FAIL (`uninitialized constant Events`).

- [ ] **Step 3: Implement**

`app/domain/audit_identity.rb`:

```ruby
# Stamped into Go-owned updated_by columns so the Go side's history shows
# exactly which admin changed a row from this app.
module AuditIdentity
  def self.for(actor) = "carbonmice-admin:#{actor.email_address}"
end
```

`app/domain/ports/event_repository.rb`:

```ruby
module Ports
  # Contract:
  #   find(id) -> event record | raises Ports::NotFound (unknown OR malformed uuid)
  #   list(search: nil, status: nil, page: 1) -> up to PAGE_SIZE+1 events, newest first
  #     (the +1 row signals "has next page" to the caller)
  #   update_status(id, to:, updated_by:) -> record
  #   update_details(id, attrs, updated_by:) -> record | raises Ports::ValidationFailed
  # Records respond to: id, name_thai, name_eng, event_status, area_name,
  # province, created_by, created_at. Never exposes soft-deleted rows.
  module EventRepository
  end
end
```

`app/domain/events/change_status.rb`:

```ruby
module Events
  class ChangeStatus
    # allowed[new_status] = statuses an event may move FROM.
    # Mirrors the Go backend's ValidateStatus map (internal/model/event.go:444)
    # exactly, EXCEPT two targets are intentionally absent:
    # - "pending_email_confirm": in Go, entering this status normally happens
    #   via EscalateEventStatus (verification email + quota deduction) which
    #   this app cannot replicate; the PATCH-only backward correction
    #   email_confirmed→pending_email_confirm is conservatively omitted too.
    # - "quotation": not a row in the event_statuses catalog; Go-internal.
    # NOTE: Go's table is mostly BACKWARD corrections (the forward flow lives
    # in EscalateEventStatus) — that suits an admin correction tool exactly.
    # Admin changes are silent: no emails, no quota changes — every change
    # lands in the audit log instead.
    TRANSITIONS = {
      "draft"            => ["draft", "pending_email_confirm", ""].freeze,
      "email_confirmed"  => ["survey_published"].freeze,
      "quotation_review" => ["quotation"].freeze,
      "survey_published" => ["collecting"].freeze,
      "collecting"       => ["quotation_review", "reject"].freeze,
      "in_progress"      => ["collecting"].freeze,
      "done"             => ["in_progress"].freeze,
      "complete"         => ["done", "collecting"].freeze,
      "carbon_credit"    => ["complete"].freeze,
      "offset_carbon"    => ["complete", "carbon_credit"].freeze,
      "send_data"        => ["complete", "offset_carbon"].freeze,
      "reject"           => ["in_progress"].freeze
    }.freeze

    def self.call(actor:, id:, to:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      to = to.to_s
      allowed_from = TRANSITIONS[to]
      return Result.failure("สถานะปลายทางไม่ถูกต้อง") unless allowed_from

      event = repo.find(id)
      from = event.event_status.to_s
      unless allowed_from.include?(from)
        from_label = from.empty? ? "(ว่าง)" : from
        return Result.failure("เปลี่ยนสถานะจาก #{from_label} ไป #{to} ไม่ได้")
      end

      record = repo.update_status(id, to: to, updated_by: AuditIdentity.for(actor))
      audit.record(action: "events.status_changed", actor: actor, target: record,
                   changes: { "event_status" => { "from" => from, "to" => to } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบอีเว้นท์")
    end
  end
end
```

- [ ] **Step 4: Run** — `ruby -Itest test/domain/events/change_status_test.rb` → PASS, 6 runs. Also `bin/rails test` still green.

- [ ] **Step 5: Commit** — `feat: audited event status transitions mirroring Go rules`

---

### Task 4: `Events::UpdateDetails` — pure domain, TDD

**Files:**
- Create: `app/domain/events/update_details.rb`
- Test: `test/domain/events/update_details_test.rb`

- [ ] **Step 1: Write the failing test** — `test/domain/events/update_details_test.rb`

```ruby
require_relative "../../domain_helper"

FakeDetailEvent = Struct.new(:id, :name_thai, :name_eng, :area_name, :province, :updated_by,
                             keyword_init: true)

class FakeDetailRepo
  attr_reader :rows
  def initialize(rows) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def update_details(id, attrs, updated_by:)
    row = find(id)
    attrs.each { |k, v| row[k] = v }
    row.updated_by = updated_by
    row
  end
end

class UpdateDetailsTest < Minitest::Test
  def setup
    @audit_entries = []
    audit_entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| audit_entries << entry }
    @superadmin = Struct.new(:id, :role, :email_address).new(1, "superadmin", "sa@pea.co.th")
    @repo = FakeDetailRepo.new(
      "e1" => FakeDetailEvent.new(id: "e1", name_thai: "ชื่อเดิม", name_eng: "Old", province: "กรุงเทพมหานคร")
    )
  end

  def test_updates_whitelisted_fields_and_audits_diff
    result = Events::UpdateDetails.call(actor: @superadmin, id: "e1",
                                        attrs: { name_thai: "ชื่อใหม่" }, repo: @repo, audit: @audit)
    assert result.success?
    assert_equal "ชื่อใหม่", @repo.find("e1").name_thai
    assert_equal({ "name_thai" => { "from" => "ชื่อเดิม", "to" => "ชื่อใหม่" } },
                 @audit_entries.last[:changes])
    assert_equal "events.updated", @audit_entries.last[:action]
  end

  def test_rejects_fields_outside_the_whitelist
    result = Events::UpdateDetails.call(actor: @superadmin, id: "e1",
                                        attrs: { event_status: "done" }, repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_rejects_empty_payload
    result = Events::UpdateDetails.call(actor: @superadmin, id: "e1",
                                        attrs: {}, repo: @repo, audit: @audit)
    assert result.failure?
  end

  def test_non_manager_is_denied
    viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    result = Events::UpdateDetails.call(actor: viewer, id: "e1",
                                        attrs: { name_thai: "x" }, repo: @repo, audit: @audit)
    assert result.failure?
  end
end
```

- [ ] **Step 2: Run** — FAIL (`uninitialized constant Events::UpdateDetails`).

- [ ] **Step 3: Implement** — `app/domain/events/update_details.rb`

```ruby
module Events
  class UpdateDetails
    # Descriptive fields only. Everything else on events is either
    # Go-computed (quota_deducted, payment_status, snapshots) or has its
    # own audited path (event_status via Events::ChangeStatus).
    EDITABLE = [:name_thai, :name_eng, :area_name, :province].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [k.to_s, before.public_send(k)] }
      record = repo.update_details(id, attrs, updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) }] }
      audit.record(action: "events.updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบอีเว้นท์")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

- [ ] **Step 4: Run** — PASS, 4 runs. `bin/rails test` green.
- [ ] **Step 5: Commit** — `feat: audited editing of safe event fields`

---

### Task 5: `Persistence::ArEventRepository` — adapter, TDD

**Files:**
- Create: `app/adapters/persistence/ar_event_repository.rb`
- Test: `test/adapters/ar_event_repository_test.rb`

- [ ] **Step 1: Write the failing test** — `test/adapters/ar_event_repository_test.rb`

```ruby
require "test_helper"

class ArEventRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::ArEventRepository.new }

  test "find raises NotFound for unknown and malformed ids" do
    assert_raises(Ports::NotFound) { @repo.find(SecureRandom.uuid) }
    assert_raises(Ports::NotFound) { @repo.find("not-a-uuid") }
  end

  test "find excludes soft-deleted events" do
    event = create_core_event!
    ActiveRecord::Base.connection.execute(
      "UPDATE public.events SET deleted_at = now() WHERE id = '#{event.id}'"
    )
    assert_raises(Ports::NotFound) { @repo.find(event.id) }
  end

  test "list searches both names and filters by status" do
    create_core_event!(name_thai: "งานหนังสือ", name_eng: "Book Fair", status: "collecting")
    create_core_event!(name_thai: "งานวิ่ง", name_eng: "Run", status: "draft")

    assert_equal 1, @repo.list(search: "หนังสือ").size
    assert_equal 1, @repo.list(search: "book").size          # ILIKE, case-insensitive
    assert_equal 1, @repo.list(status: "draft").size
    assert_equal 0, @repo.list(search: "100%งาน").size       # LIKE wildcards escaped
  end

  test "list paginates with a has-next sentinel row" do
    (Persistence::ArEventRepository::PAGE_SIZE + 1).times { |i| create_core_event!(name_eng: "E#{i}") }
    page1 = @repo.list(page: 1)
    assert_equal Persistence::ArEventRepository::PAGE_SIZE + 1, page1.size
    page2 = @repo.list(page: 2)
    assert_equal 1, page2.size
  end

  test "update_status stamps updated_by" do
    event = create_core_event!(status: "collecting")
    @repo.update_status(event.id, to: "in_progress", updated_by: "carbonmice-admin:sa@pea.co.th")
    event.reload
    assert_equal "in_progress", event.event_status
    assert_equal "carbonmice-admin:sa@pea.co.th", event.updated_by
  end

  test "update_details writes only given attrs" do
    event = create_core_event!(name_thai: "เดิม", province: "เชียงใหม่")
    @repo.update_details(event.id, { name_thai: "ใหม่" }, updated_by: "carbonmice-admin:sa@pea.co.th")
    event.reload
    assert_equal "ใหม่", event.name_thai
    assert_equal "เชียงใหม่", event.province
  end
end
```

- [ ] **Step 2: Run** — FAIL (`uninitialized constant Persistence::ArEventRepository`).

- [ ] **Step 3: Implement** — `app/adapters/persistence/ar_event_repository.rb`

```ruby
module Persistence
  class ArEventRepository
    PAGE_SIZE = 25

    def find(id)
      Core::Event.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      # StatementInvalid: malformed uuid strings must read as "not found",
      # not a 500 (lesson from the admin_users padded-id review).
      raise Ports::NotFound
    end

    def list(search: nil, status: nil, page: 1)
      scope = Core::Event.kept.order(created_at: :desc)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("name_thai ILIKE :q OR name_eng ILIKE :q", q: q)
      end
      scope = scope.where(event_status: status) if status.present?
      page = [page.to_i, 1].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def update_status(id, to:, updated_by:)
      record = find(id)
      record.update!(event_status: to, updated_by: updated_by)
      record
    end

    def update_details(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end
  end
end
```

- [ ] **Step 4: Run** — PASS, 6 runs. Full suite green.
- [ ] **Step 5: Commit** — `feat: event repository adapter with search, pagination and stamped writes`

---

### Task 6: Events web — index + show (readable by every role)

**Files:**
- Create: `app/controllers/events_controller.rb`, `app/views/events/index.html.erb`, `app/views/events/show.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/events_controller_test.rb`

- [ ] **Step 1: Write the failing test** — `test/controllers/events_controller_test.rb`

```ruby
require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists events with search and status filter" do
    login(@superadmin)
    create_core_event!(name_thai: "งานหนังสือ", status: "collecting")
    create_core_event!(name_thai: "งานวิ่ง", status: "draft")

    get events_path
    assert_response :success
    assert_select "td", text: "งานหนังสือ"

    get events_path, params: { search: "หนังสือ" }
    assert_select "td", text: "งานหนังสือ"
    assert_select "td", text: "งานวิ่ง", count: 0

    get events_path, params: { status: "draft" }
    assert_select "td", text: "งานวิ่ง"
    assert_select "td", text: "งานหนังสือ", count: 0
  end

  test "viewer can read the list and detail but sees no edit controls" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    event = create_core_event!(name_thai: "งานอ่านได้")
    get events_path
    assert_response :success
    get event_path(event.id)
    assert_response :success
    assert_select "form[action=?]", status_event_path(event.id), count: 0
    assert_select "a[href=?]", edit_event_path(event.id), count: 0
  end

  test "detail shows emissions per category" do
    login(@superadmin)
    event = create_core_event!(name_thai: "งานคาร์บอน")
    create_core_emission!(event_id: event.id, category_thai: "การเดินทาง", pre: 12.5)
    get event_path(event.id)
    assert_response :success
    assert_select "td", text: "การเดินทาง"
  end

  test "unknown event id redirects with alert" do
    login(@superadmin)
    get event_path("not-a-uuid")
    assert_redirected_to events_path
  end
end
```

- [ ] **Step 2: Run** — FAIL (undefined `events_path`).

- [ ] **Step 3: Implement**

`config/routes.rb` — add:

```ruby
  resources :events, only: %i[index show edit update] do
    member { patch :status }
  end
```

`app/controllers/events_controller.rb` (edit/update/status bodies arrive in Task 7 — include them now so routes resolve, full file):

```ruby
class EventsController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: %i[index show]
  before_action -> { authorize!(:manage_events) }, only: %i[edit update status]
  before_action :load_event, only: %i[show edit]

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(search: params[:search].presence, status: params[:status].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArEventRepository::PAGE_SIZE
    @events = rows.first(Persistence::ArEventRepository::PAGE_SIZE)
    @page = page
    @statuses = Core::EventStatus.ordered
  end

  def show
    @emissions = Core::CarbonEmission.where(event_id: @event.id)
                                     .includes(:carbon_category, :unit)
    @status_targets = Events::ChangeStatus::TRANSITIONS
                        .select { |_to, froms| froms.include?(@event.event_status.to_s) }
                        .keys
  end

  def edit
  end

  def update
    result = Events::UpdateDetails.call(actor: current_admin, id: params[:id],
                                        attrs: update_params.to_h.symbolize_keys,
                                        repo: repo, audit: audit)
    if result.success?
      redirect_to event_path(params[:id]), notice: "บันทึกการแก้ไขแล้ว"
    else
      redirect_to edit_event_path(params[:id]), alert: result.error
    end
  rescue Ports::NotFound
    redirect_to events_path, alert: "ไม่พบอีเว้นท์"
  end

  def status
    result = Events::ChangeStatus.call(actor: current_admin, id: params[:id],
                                       to: params[:to].to_s, repo: repo, audit: audit)
    if result.success?
      redirect_to event_path(params[:id]), notice: "เปลี่ยนสถานะแล้ว"
    else
      redirect_to event_path(params[:id]), alert: result.error
    end
  rescue Ports::NotFound
    redirect_to events_path, alert: "ไม่พบอีเว้นท์"
  end

  private
    def load_event
      @event = repo.find(params[:id])
    rescue Ports::NotFound
      redirect_to events_path, alert: "ไม่พบอีเว้นท์"
    end

    def update_params = params.require(:event).permit(:name_thai, :name_eng, :area_name, :province)
    def repo = Persistence::ArEventRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
```

`app/views/events/index.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">อีเว้นท์</h1>

<%= form_with url: events_path, method: :get, class: "mt-4 flex flex-wrap items-end gap-3" do |f| %>
  <div>
    <%= f.label :search, "ค้นหา", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.text_field :search, value: params[:search], placeholder: "ชื่ออีเว้นท์ (ไทย/อังกฤษ)",
          class: "w-72 rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <div>
    <%= f.label :status, "สถานะ", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.select :status,
          [["ทั้งหมด", ""]] + @statuses.map { |s| ["#{s.name_thai} (#{s.name_eng})", s.name_eng] },
          { selected: params[:status] }, class: "rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <%= f.submit "กรอง", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>

<table class="mt-6 w-full rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">ชื่อ (ไทย)</th>
      <th class="px-4 py-3">ชื่อ (อังกฤษ)</th>
      <th class="px-4 py-3">สถานะ</th>
      <th class="px-4 py-3">จังหวัด</th>
      <th class="px-4 py-3">สร้างเมื่อ</th>
      <th class="px-4 py-3"></th>
    </tr>
  </thead>
  <tbody>
    <% @events.each do |event| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3 font-medium text-ink"><%= event.name_thai %></td>
        <td class="px-4 py-3"><%= event.name_eng %></td>
        <td class="px-4 py-3"><span class="rounded-full bg-blue-50 px-3 py-1 text-primary"><%= event.event_status %></span></td>
        <td class="px-4 py-3"><%= event.province %></td>
        <td class="px-4 py-3 whitespace-nowrap"><%= event.created_at&.in_time_zone&.strftime("%d/%m/%Y") %></td>
        <td class="px-4 py-3 text-right"><%= link_to "ดูรายละเอียด", event_path(event.id), class: "text-primary" %></td>
      </tr>
    <% end %>
  </tbody>
</table>

<div class="mt-4 flex items-center gap-3">
  <% if @page > 1 %>
    <%= link_to "← ก่อนหน้า", events_path(search: params[:search], status: params[:status], page: @page - 1), class: "text-primary" %>
  <% end %>
  <span class="text-sm text-body/60">หน้า <%= @page %></span>
  <% if @has_next %>
    <%= link_to "ถัดไป →", events_path(search: params[:search], status: params[:status], page: @page + 1), class: "text-primary" %>
  <% end %>
</div>
```

`app/views/events/show.html.erb`:

```erb
<div class="flex items-center justify-between">
  <h1 class="text-2xl font-bold text-ink"><%= @event.name_thai.presence || @event.name_eng %></h1>
  <% if can?(:manage_events) %>
    <%= link_to "แก้ไขข้อมูล", edit_event_path(@event.id),
          class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark" %>
  <% end %>
</div>

<dl class="mt-6 grid max-w-3xl grid-cols-2 gap-x-8 gap-y-3 rounded-xl bg-white p-6 shadow-sm text-sm">
  <dt class="font-medium text-body/60">ชื่อ (อังกฤษ)</dt><dd class="text-ink"><%= @event.name_eng %></dd>
  <dt class="font-medium text-body/60">สถานะปัจจุบัน</dt><dd><span class="rounded-full bg-blue-50 px-3 py-1 text-primary"><%= @event.event_status %></span></dd>
  <dt class="font-medium text-body/60">สถานที่</dt><dd class="text-ink"><%= @event.area_name %></dd>
  <dt class="font-medium text-body/60">จังหวัด</dt><dd class="text-ink"><%= @event.province %></dd>
  <dt class="font-medium text-body/60">สร้างโดย (raw id)</dt><dd class="font-mono text-xs"><%= @event.created_by %></dd>
  <dt class="font-medium text-body/60">สร้างเมื่อ</dt><dd><%= @event.created_at&.in_time_zone&.strftime("%d/%m/%Y %H:%M") %></dd>
</dl>

<% if can?(:manage_events) %>
  <div class="mt-6 max-w-3xl rounded-xl bg-white p-6 shadow-sm">
    <h2 class="font-semibold text-ink">เปลี่ยนสถานะ</h2>
    <p class="mt-1 text-sm text-body/60">
      การเปลี่ยนสถานะจากหน้านี้เป็นการแก้ไขข้อมูลโดยตรง — ไม่ส่งอีเมลและไม่หักโควต้า
      (ระบบหลักเท่านั้นที่ทำขั้นตอนเหล่านั้น) ทุกการเปลี่ยนถูกบันทึกใน audit log
    </p>
    <% if @status_targets.any? %>
      <%= form_with url: status_event_path(@event.id), method: :patch, class: "mt-3 flex items-end gap-3" do |f| %>
        <%= f.select :to, @status_targets.map { |s| [s, s] }, {}, class: "rounded-lg border border-gray-300 px-3 py-2" %>
        <%= f.submit "เปลี่ยนสถานะ", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
      <% end %>
    <% else %>
      <p class="mt-3 text-sm text-body/60">ไม่มีสถานะปลายทางที่เปลี่ยนได้จากสถานะปัจจุบัน</p>
    <% end %>
  </div>
<% end %>

<h2 class="mt-8 text-xl font-bold text-ink">การปล่อยคาร์บอน</h2>
<% if @emissions.any? %>
  <table class="mt-3 w-full max-w-3xl rounded-xl bg-white shadow-sm text-sm">
    <thead>
      <tr class="border-b border-gray-200 text-left text-body/60">
        <th class="px-4 py-3">หมวด</th>
        <th class="px-4 py-3">ก่อนจัดงาน</th>
        <th class="px-4 py-3">หลังจัดงาน</th>
        <th class="px-4 py-3">หน่วย</th>
      </tr>
    </thead>
    <tbody>
      <% @emissions.each do |e| %>
        <tr class="border-b border-gray-100">
          <td class="px-4 py-3 font-medium text-ink"><%= e.carbon_category.name_thai %></td>
          <td class="px-4 py-3"><%= e.pre_event_emission %></td>
          <td class="px-4 py-3"><%= e.post_event_emission || "—" %></td>
          <td class="px-4 py-3"><%= e.unit.code %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p class="mt-3 text-sm text-body/60">ยังไม่มีข้อมูลการปล่อยคาร์บอน</p>
<% end %>
```

- [ ] **Step 4: Run** — `bin/rails test test/controllers/events_controller_test.rb` → PASS, 4 runs (the edit view 404s are Task 7's; these tests don't render edit). Full suite green.
- [ ] **Step 5: Commit** — `feat: event list with search/filter/pagination and detail with emissions`

---

### Task 7: Events web — edit form + status change behavior

**Files:**
- Create: `app/views/events/edit.html.erb`
- Test: append to `test/controllers/events_controller_test.rb`

- [ ] **Step 1: Failing tests** — append inside `EventsControllerTest`:

```ruby
  test "superadmin edits safe fields with an audit diff" do
    login(@superadmin)
    event = create_core_event!(name_thai: "เดิม")
    get edit_event_path(event.id)
    assert_response :success

    assert_difference -> { AuditLog.where(action: "events.updated").count } => 1 do
      patch event_path(event.id), params: { event: { name_thai: "ใหม่", province: "ขอนแก่น" } }
    end
    assert_redirected_to event_path(event.id)
    assert_equal "ใหม่", event.reload.name_thai
    log = AuditLog.where(action: "events.updated").order(:id).last
    assert_equal "ใหม่", log.change_set.dig("name_thai", "to")
  end

  test "status change follows the transition table and audits" do
    login(@superadmin)
    event = create_core_event!(status: "collecting")
    assert_difference -> { AuditLog.where(action: "events.status_changed").count } => 1 do
      patch status_event_path(event.id), params: { to: "in_progress" }
    end
    assert_equal "in_progress", event.reload.event_status

    assert_no_difference -> { AuditLog.where(action: "events.status_changed").count } do
      patch status_event_path(event.id), params: { to: "draft" }   # not allowed from in_progress
    end
    assert_equal "in_progress", event.reload.event_status
  end

  test "viewer cannot change status or edit" do
    viewer = AdminUser.create!(email_address: "v2@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    event = create_core_event!(status: "collecting")
    patch status_event_path(event.id), params: { to: "in_progress" }
    assert_redirected_to root_path
    assert_equal "collecting", event.reload.event_status
    patch event_path(event.id), params: { event: { name_thai: "ห้าม" } }
    assert_redirected_to root_path
  end
```

- [ ] **Step 2: Run** — edit GET FAILs (missing template `events/edit`); the rest may partially pass.

- [ ] **Step 3: Implement** — `app/views/events/edit.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">แก้ไขอีเว้นท์: <%= @event.name_thai.presence || @event.name_eng %></h1>
<p class="mt-1 text-sm text-body/60">แก้ไขได้เฉพาะข้อมูลบรรยาย — สถานะ/การคำนวณ/การเงินเป็นของระบบหลัก</p>

<%= form_with url: event_path(@event.id), method: :patch, scope: :event, class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :name_thai, "ชื่อ (ไทย)", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name_thai, value: @event.name_thai, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :name_eng, "ชื่อ (อังกฤษ)", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name_eng, value: @event.name_eng, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :area_name, "สถานที่", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :area_name, value: @event.area_name, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :province, "จังหวัด", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :province, value: @event.province, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

- [ ] **Step 4: Run** — events controller tests PASS (7 runs). Full suite green.
- [ ] **Step 5: Commit** — `feat: event editing UI with audited status corrections`

---

### Task 8: App users — domain + port + adapter (TDD)

**Files:**
- Create: `app/domain/ports/app_user_repository.rb`, `app/domain/app_users/change_role.rb`, `app/domain/app_users/adjust_quota.rb`, `app/adapters/persistence/ar_app_user_repository.rb`
- Test: `test/domain/app_users/manage_app_users_test.rb`, `test/adapters/ar_app_user_repository_test.rb`

- [ ] **Step 1: Failing domain test** — `test/domain/app_users/manage_app_users_test.rb`

```ruby
require_relative "../../domain_helper"

FakeAppUser = Struct.new(:id, :email, :display_name, :role, :event_quota, :updated_by,
                         keyword_init: true)

class FakeAppUserRepo
  attr_reader :rows
  def initialize(rows) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def update_role(id, role:, updated_by:)
    row = find(id)
    row.role = role
    row.updated_by = updated_by
    row
  end
  def update_quota(id, quota:, updated_by:)
    row = find(id)
    row.event_quota = quota
    row.updated_by = updated_by
    row
  end
end

class ManageAppUsersTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @actor = Struct.new(:id, :role, :email_address).new(1, "admin", "ad@pea.co.th")
    @repo = FakeAppUserRepo.new(
      "u1" => FakeAppUser.new(id: "u1", email: "u@x.com", role: "user", event_quota: 2)
    )
  end

  def test_change_role_audits_diff
    result = AppUsers::ChangeRole.call(actor: @actor, id: "u1", role: "admin",
                                       repo: @repo, audit: @audit)
    assert result.success?
    assert_equal "admin", @repo.find("u1").role
    assert_equal "carbonmice-admin:ad@pea.co.th", @repo.find("u1").updated_by
    assert_equal({ "role" => { "from" => "user", "to" => "admin" } }, @audit_entries.last[:changes])
    assert_equal "app_users.role_changed", @audit_entries.last[:action]
  end

  def test_unknown_role_is_rejected
    result = AppUsers::ChangeRole.call(actor: @actor, id: "u1", role: "god",
                                       repo: @repo, audit: @audit)
    assert result.failure?
    assert_equal "user", @repo.find("u1").role
  end

  def test_adjust_quota_audits_diff
    result = AppUsers::AdjustQuota.call(actor: @actor, id: "u1", quota: "5",
                                        repo: @repo, audit: @audit)
    assert result.success?
    assert_equal 5, @repo.find("u1").event_quota
    assert_equal({ "event_quota" => { "from" => 2, "to" => 5 } }, @audit_entries.last[:changes])
  end

  def test_negative_or_garbage_quota_is_rejected
    assert AppUsers::AdjustQuota.call(actor: @actor, id: "u1", quota: "-1",
                                      repo: @repo, audit: @audit).failure?
    assert AppUsers::AdjustQuota.call(actor: @actor, id: "u1", quota: "many",
                                      repo: @repo, audit: @audit).failure?
    assert_equal 2, @repo.find("u1").event_quota
  end

  def test_viewer_is_denied
    viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    assert AppUsers::ChangeRole.call(actor: viewer, id: "u1", role: "admin",
                                     repo: @repo, audit: @audit).failure?
    assert AppUsers::AdjustQuota.call(actor: viewer, id: "u1", quota: 1,
                                      repo: @repo, audit: @audit).failure?
    assert_empty @audit_entries
  end
end
```

- [ ] **Step 2: Run** — `ruby -Itest test/domain/app_users/manage_app_users_test.rb` → FAIL.

- [ ] **Step 3: Implement domain**

`app/domain/ports/app_user_repository.rb`:

```ruby
module Ports
  # Contract:
  #   find(id) -> app-user record | raises Ports::NotFound (unknown/malformed uuid)
  #   list(search: nil, page: 1) -> up to PAGE_SIZE+1 users, newest first
  #   update_role(id, role:, updated_by:) -> record
  #   update_quota(id, quota:, updated_by:) -> record
  # Records respond to: id, email, display_name, role, event_quota,
  # is_package_user, created_at. Soft-deleted rows are never exposed.
  module AppUserRepository
  end
end
```

`app/domain/app_users/change_role.rb`:

```ruby
module AppUsers
  class ChangeRole
    # Role strings used by the Go backend (internal user model).
    ROLES = ["user", "admin", "super_admin"].freeze

    def self.call(actor:, id:, role:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการผู้ใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_app_users)
      role = role.to_s
      return Result.failure("สิทธิ์ไม่ถูกต้อง") unless ROLES.include?(role)

      before = repo.find(id)
      from = before.role
      record = repo.update_role(id, role: role, updated_by: AuditIdentity.for(actor))
      audit.record(action: "app_users.role_changed", actor: actor, target: record,
                   changes: { "role" => { "from" => from, "to" => role } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบผู้ใช้งาน")
    end
  end
end
```

`app/domain/app_users/adjust_quota.rb`:

```ruby
module AppUsers
  class AdjustQuota
    def self.call(actor:, id:, quota:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการผู้ใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_app_users)

      quota = begin
        Integer(quota)
      rescue ArgumentError, TypeError
        nil
      end
      return Result.failure("โควต้าต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป") if quota.nil? || quota.negative?

      before = repo.find(id)
      from = before.event_quota
      record = repo.update_quota(id, quota: quota, updated_by: AuditIdentity.for(actor))
      audit.record(action: "app_users.quota_adjusted", actor: actor, target: record,
                   changes: { "event_quota" => { "from" => from, "to" => quota } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบผู้ใช้งาน")
    end
  end
end
```

- [ ] **Step 4: Run domain test** — PASS, 5 runs.

- [ ] **Step 5: Failing adapter test** — `test/adapters/ar_app_user_repository_test.rb`

```ruby
require "test_helper"

class ArAppUserRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::ArAppUserRepository.new }

  test "find raises NotFound for unknown and malformed ids" do
    assert_raises(Ports::NotFound) { @repo.find(SecureRandom.uuid) }
    assert_raises(Ports::NotFound) { @repo.find("oops") }
  end

  test "list searches email and display name" do
    create_core_user!(email: "somchai@example.com", display_name: "สมชาย ใจดี")
    create_core_user!(email: "other@example.com", display_name: "คนอื่น")
    assert_equal 1, @repo.list(search: "somchai").size
    assert_equal 1, @repo.list(search: "สมชาย").size
    assert_equal 2, @repo.list.size
  end

  test "update_role and update_quota stamp updated_by" do
    user = create_core_user!(email: "stamp@example.com", role: "user", quota: 0)
    @repo.update_role(user.id, role: "admin", updated_by: "carbonmice-admin:sa@pea.co.th")
    @repo.update_quota(user.id, quota: 7, updated_by: "carbonmice-admin:sa@pea.co.th")
    user.reload
    assert_equal "admin", user.role
    assert_equal 7, user.event_quota
    assert_equal "carbonmice-admin:sa@pea.co.th", user.updated_by
  end
end
```

- [ ] **Step 6: Implement adapter** — `app/adapters/persistence/ar_app_user_repository.rb`

```ruby
module Persistence
  class ArAppUserRepository
    PAGE_SIZE = 25

    def find(id)
      Core::User.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(search: nil, page: 1)
      scope = Core::User.kept.order(created_at: :desc)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("email ILIKE :q OR display_name ILIKE :q", q: q)
      end
      page = [page.to_i, 1].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def update_role(id, role:, updated_by:)
      record = find(id)
      record.update!(role: role, updated_by: updated_by)
      record
    end

    def update_quota(id, quota:, updated_by:)
      record = find(id)
      record.update!(event_quota: quota, updated_by: updated_by)
      record
    end
  end
end
```

- [ ] **Step 7: Run** — adapter test PASS (3 runs); full suite + standalone domain files green.
- [ ] **Step 8: Commit** — `feat: app-user role and quota management with audited writes`

---

### Task 9: App users web — index + edit

**Files:**
- Create: `app/controllers/app_users_controller.rb`, `app/views/app_users/index.html.erb`, `app/views/app_users/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/app_users_controller_test.rb`

- [ ] **Step 1: Failing test** — `test/controllers/app_users_controller_test.rb`

```ruby
require "test_helper"

class AppUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists and searches app users" do
    login(@superadmin)
    create_core_user!(email: "somchai@example.com", display_name: "สมชาย")
    create_core_user!(email: "other@example.com", display_name: "คนอื่น")
    get app_users_path
    assert_response :success
    assert_select "td", text: "somchai@example.com"
    get app_users_path, params: { search: "สมชาย" }
    assert_select "td", text: "somchai@example.com"
    assert_select "td", text: "other@example.com", count: 0
  end

  test "updates role and quota with audit entries" do
    login(@superadmin)
    user = create_core_user!(email: "t@example.com", role: "user", quota: 1)
    assert_difference -> { AuditLog.where(action: "app_users.role_changed").count } => 1,
                      -> { AuditLog.where(action: "app_users.quota_adjusted").count } => 1 do
      patch app_user_path(user.id), params: { app_user: { role: "admin", event_quota: "9" } }
    end
    user.reload
    assert_equal "admin", user.role
    assert_equal 9, user.event_quota
  end

  test "unchanged values do not produce audit noise" do
    login(@superadmin)
    user = create_core_user!(email: "same@example.com", role: "user", quota: 4)
    assert_no_difference -> { AuditLog.count } do
      patch app_user_path(user.id), params: { app_user: { role: "user", event_quota: "4" } }
    end
  end

  test "viewer can read but not write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    user = create_core_user!(email: "ro@example.com")
    get app_users_path
    assert_response :success
    patch app_user_path(user.id), params: { app_user: { role: "admin" } }
    assert_redirected_to root_path
    assert_equal "user", user.reload.role
  end
end
```

- [ ] **Step 2: Run** — FAIL (undefined `app_users_path`).

- [ ] **Step 3: Implement**

`config/routes.rb` — add: `resources :app_users, only: %i[index edit update]`

`app/controllers/app_users_controller.rb`:

```ruby
class AppUsersController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_app_users) }, only: %i[edit update]

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(search: params[:search].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArAppUserRepository::PAGE_SIZE
    @app_users = rows.first(Persistence::ArAppUserRepository::PAGE_SIZE)
    @page = page
  end

  def edit
    @app_user = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to app_users_path, alert: "ไม่พบผู้ใช้งาน"
  end

  # Role and quota changes are independent audited use cases; only the
  # fields that actually changed run (no audit noise for no-ops).
  def update
    current = repo.find(params[:id])
    errors = []

    if update_params[:role].present? && update_params[:role] != current.role
      result = AppUsers::ChangeRole.call(actor: current_admin, id: params[:id],
                                         role: update_params[:role], repo: repo, audit: audit)
      errors << result.error if result.failure?
    end

    if update_params[:event_quota].present? && update_params[:event_quota].to_s != current.event_quota.to_s
      result = AppUsers::AdjustQuota.call(actor: current_admin, id: params[:id],
                                          quota: update_params[:event_quota], repo: repo, audit: audit)
      errors << result.error if result.failure?
    end

    if errors.empty?
      redirect_to app_users_path, notice: "บันทึกการแก้ไขแล้ว"
    else
      redirect_to edit_app_user_path(params[:id]), alert: errors.join(" / ")
    end
  rescue Ports::NotFound
    redirect_to app_users_path, alert: "ไม่พบผู้ใช้งาน"
  end

  private
    def update_params = params.require(:app_user).permit(:role, :event_quota)
    def repo = Persistence::ArAppUserRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
```

`app/views/app_users/index.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">ผู้ใช้งานระบบหลัก</h1>

<%= form_with url: app_users_path, method: :get, class: "mt-4 flex items-end gap-3" do |f| %>
  <div>
    <%= f.label :search, "ค้นหา", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.text_field :search, value: params[:search], placeholder: "อีเมลหรือชื่อ",
          class: "w-72 rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <%= f.submit "ค้นหา", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>

<table class="mt-6 w-full rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">ชื่อ</th>
      <th class="px-4 py-3">อีเมล</th>
      <th class="px-4 py-3">สิทธิ์</th>
      <th class="px-4 py-3">โควต้าอีเว้นท์</th>
      <th class="px-4 py-3">แพ็กเกจ</th>
      <th class="px-4 py-3"></th>
    </tr>
  </thead>
  <tbody>
    <% @app_users.each do |user| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3 font-medium text-ink"><%= user.display_name %></td>
        <td class="px-4 py-3"><%= user.email %></td>
        <td class="px-4 py-3"><%= user.role %></td>
        <td class="px-4 py-3"><%= user.event_quota %></td>
        <td class="px-4 py-3"><%= user.is_package_user ? "ใช่" : "—" %></td>
        <td class="px-4 py-3 text-right">
          <% if can?(:manage_app_users) %>
            <%= link_to "แก้ไข", edit_app_user_path(user.id), class: "text-primary" %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<div class="mt-4 flex items-center gap-3">
  <% if @page > 1 %>
    <%= link_to "← ก่อนหน้า", app_users_path(search: params[:search], page: @page - 1), class: "text-primary" %>
  <% end %>
  <span class="text-sm text-body/60">หน้า <%= @page %></span>
  <% if @has_next %>
    <%= link_to "ถัดไป →", app_users_path(search: params[:search], page: @page + 1), class: "text-primary" %>
  <% end %>
</div>
```

`app/views/app_users/edit.html.erb`:

```erb
<h1 class="text-2xl font-bold text-ink">แก้ไขผู้ใช้งาน: <%= @app_user.email %></h1>

<%= form_with url: app_user_path(@app_user.id), method: :patch, scope: :app_user, class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :role, "สิทธิ์", class: "mb-1 block font-medium text-ink" %>
    <%= f.select :role, AppUsers::ChangeRole::ROLES.map { |r| [r, r] },
          { selected: @app_user.role }, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :event_quota, "โควต้าอีเว้นท์", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :event_quota, value: @app_user.event_quota, min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

- [ ] **Step 4: Run** — PASS, 4 runs. Full suite green.
- [ ] **Step 5: Commit** — `feat: app-user management UI (role, quota) with audit`

---

### Task 10: Navigation, Thai role labels, audit filter options, README — final green

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`, `app/helpers/application_helper.rb`, `app/views/admin_users/index.html.erb`, `app/views/audit_logs/index.html.erb`, `test/controllers/home_controller_test.rb`, `README.md`

- [ ] **Step 1: Failing tests** — in `test/controllers/home_controller_test.rb`, replace the viewer test and add nav expectations:

```ruby
  test "all roles see events and app-users links" do
    login_as(:viewer)
    get root_path
    assert_select "nav a[href=?]", "/events"
    assert_select "nav a[href=?]", "/app_users"
  end
```

And update the existing "viewer sees only the home link" test name/body to "viewer sees no management links" keeping its `/admin_users` + `/audit_logs` count-0 assertions and the `"/"` count-1 assertion.

- [ ] **Step 2: Run** — FAIL (no events link in nav).

- [ ] **Step 3: Implement**

`app/views/shared/_sidebar.html.erb` — inside `<nav>`, after the หน้าหลัก link add:

```erb
    <% if can?(:view_operations) %>
      <%= link_to "อีเว้นท์", events_path, class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
      <%= link_to "ผู้ใช้งาน", app_users_path, class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
    <% end %>
```

And change the role line in the footer to `<%= role_label(current_admin.role) %>`.

`app/helpers/application_helper.rb`:

```ruby
module ApplicationHelper
  ROLE_LABELS = {
    "superadmin"  => "ผู้ดูแลสูงสุด",
    "admin"       => "ผู้ดูแล",
    "viewer"      => "ผู้ชม",
    # Go-side app user roles
    "super_admin" => "ผู้ดูแลสูงสุด (ระบบหลัก)",
    "user"        => "ผู้ใช้ทั่วไป",
    "visitor"     => "ผู้เยี่ยมชม"
  }.freeze

  def role_label(role) = ROLE_LABELS.fetch(role.to_s, role.to_s)
end
```

In `app/views/admin_users/index.html.erb` change `<%= admin.role %>` to `<%= role_label(admin.role) %>`.

In `app/views/audit_logs/index.html.erb` extend the ประเภท select options to:

```erb
          [["ทั้งหมด", ""], ["การเข้าสู่ระบบ", "auth."], ["บัญชีผู้ดูแล", "admin_users."],
           ["อีเว้นท์", "events."], ["ผู้ใช้งานระบบหลัก", "app_users."]],
```

`README.md` — under Tests, add:

```markdown
- Go-schema fixture: `db/core_structure.sql` is a structure-only snapshot of the
  shared DB's `public` schema, loaded into the test DB on boot. When the Go team
  migrates, regenerate it:
  `pg_dump "$DEV_DB_URL" --schema=public --schema-only --no-owner --no-privileges | grep -v '^\\' > db/core_structure.sql`
```

And under Security notes, add:

```markdown
- Admin writes to Go-owned rows stamp `updated_by = "carbonmice-admin:<email>"`
  and are limited to: event descriptive fields, event_status (validated
  transitions, no Go-side side effects), users.role and users.event_quota.
```

- [ ] **Step 4: Full verification**

```bash
bin/rails test                                            # expect ~90 runs (52 from Plan 1 + ~38 new incl. domain files), 0 failures
for f in test/domain/**/*_test.rb; do ruby -Itest "$f"; done
bin/rubocop
bundle exec brakeman -q
```

All green / exit 0. If RuboCop flags new files, `bin/rubocop -a` then re-run tests.

- [ ] **Step 5: Commit** — `feat: navigation, Thai role labels and audit filters for Plan 2 modules`

---

## Roadmap after this plan

**Plan 3/3:** master data CRUD (emission factors full CRUD; categories name_thai-only — `name_eng` is matched as an enum in Go code and must stay read-only, same for units.code; event + carbon-offset pricing tiers), dashboard summary, Capybara system tests for critical flows, Dockerfile + GitLab CI, admin password change, session cleanup task, DB-level audit REVOKE + least-privilege role, shared cache store for the rate limiter.
