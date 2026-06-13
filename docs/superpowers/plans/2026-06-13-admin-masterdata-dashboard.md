# Carbonmice Admin — Plan 3/4: Master Data, Dashboard, Password Change & System Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins manage emission-factor master data (create/edit/soft-delete), tune pricing tiers, rename category Thai labels; the home page becomes a system dashboard; admins can change their own password; Capybara (rack_test) system tests cover the critical flows.

**Architecture:** Same hexagonal pattern as Plans 1-2. New `MasterData::` and `Dashboard::` domain modules with per-entity ports/adapters. This plan introduces the FIRST INSERTs into a Go-owned table (emission factors create) — stamped `created_by = "carbonmice-admin:<email>"` and audited, like all writes.

**Plan 4 (later):** Dockerfile + GitLab CI, DB least-privilege role + `REVOKE UPDATE/DELETE` on audit_logs, session-cleanup task, shared cache store for the rate limiter, tier create/delete if ever needed.

**Verified Go-schema facts (live DB + Go source):**
- `carbon_emission_factors` (140 live rows): name vc255 NOT NULL, description text, source text NOT NULL, value_per_unit numeric(12,6) NOT NULL, unit_title vc255 NOT NULL, identifier vc255 with UNIQUE partial index (WHERE identifier IS NOT NULL), carbon_category_id uuid NOT NULL FK, unit_id uuid nullable FK, soft-delete. Go looks factors up BY IDENTIFIER STRING (`factors["ef_..."]`) per request — edits take effect immediately EXCEPT the event-items/giveaways mapper, which embeds factors at Go startup (router.go:61) → those need a Go restart.
- `event_pricing_tiers` (3 live): min_participants int NOT NULL ≥0, max_participants int nullable (CHECK > 0 AND >= min), price_per_person numeric(10,2) NOT NULL.
- `carbon_offset_pricing_tiers` (9 live): min_emission int NOT NULL ≥0, max_emission int nullable, price_per_emission numeric(10,2) NOT NULL, unit_id uuid NOT NULL FK, carbon_offset_source_id uuid NOT NULL FK.
- `carbon_offset_sources`: name vc255 NOT NULL, name_th vc255.
- `carbon_categories` (8 rows): name_thai/name_eng NOT NULL — **name_eng is matched as an enum in Go code ("food_and_beverage" etc.): read-only forever.** Same for `units.code` ("kg"/"tons").

**Hard rules:** never modify carbonmice-main-go-be; never migrate public tables; domain files pure Ruby (no ActiveSupport); commands via `mise exec ruby@4.0.0 --` when needed; libpq at /opt/homebrew/opt/libpq/bin; suite currently 97 runs green.

---

### Task 1: Core models + factories for master data

**Files:**
- Create: `app/models/core/emission_factor.rb`, `app/models/core/event_pricing_tier.rb`, `app/models/core/carbon_offset_pricing_tier.rb`, `app/models/core/carbon_offset_source.rb`
- Modify: `test/support/core_factories.rb`
- Test: `test/models/core_master_data_test.rb`

- [x] **Step 1: failing test** — `test/models/core_master_data_test.rb`

```ruby
require "test_helper"

class CoreMasterDataTest < ActiveSupport::TestCase
  test "Core::EmissionFactor maps factors with category" do
    f = create_core_emission_factor!(identifier: "ef_test_factor", name: "ค่าทดสอบ", value: 2.5)
    found = Core::EmissionFactor.kept.find_by(identifier: "ef_test_factor")
    assert_equal 2.5, found.value_per_unit.to_f
    assert_equal "ค่าทดสอบ", found.name
    assert found.carbon_category.name_thai.present?
  end

  test "Core::EventPricingTier and Core::CarbonOffsetPricingTier map their tables" do
    t = create_core_event_pricing_tier!(min: 1, max: 100, price: 5.0)
    assert_equal 5.0, Core::EventPricingTier.kept.find(t.id).price_per_person.to_f

    src = create_core_offset_source!(name: "TGO Test", name_th: "ทีจีโอทดสอบ")
    o = create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.5)
    found = Core::CarbonOffsetPricingTier.kept.find(o.id)
    assert_equal 99.5, found.price_per_emission.to_f
    assert_equal "ทีจีโอทดสอบ", found.carbon_offset_source.name_th
  end
end
```

- [x] **Step 2: run** `bin/rails test test/models/core_master_data_test.rb` → FAIL (undefined factory / uninitialized constant).

- [x] **Step 3: implement models**

`app/models/core/emission_factor.rb`:
```ruby
module Core
  class EmissionFactor < Base
    self.table_name = "public.carbon_emission_factors"

    belongs_to :carbon_category, class_name: "Core::CarbonCategory"
    belongs_to :unit, class_name: "Core::Unit", optional: true
  end
end
```

`app/models/core/event_pricing_tier.rb`:
```ruby
module Core
  class EventPricingTier < Base
    self.table_name = "public.event_pricing_tiers"
  end
end
```

`app/models/core/carbon_offset_pricing_tier.rb`:
```ruby
module Core
  class CarbonOffsetPricingTier < Base
    self.table_name = "public.carbon_offset_pricing_tiers"

    belongs_to :carbon_offset_source, class_name: "Core::CarbonOffsetSource"
    belongs_to :unit, class_name: "Core::Unit"
  end
end
```

`app/models/core/carbon_offset_source.rb`:
```ruby
module Core
  class CarbonOffsetSource < Base
    self.table_name = "public.carbon_offset_sources"
  end
end
```

- [x] **Step 4: extend factories** — in `test/support/core_factories.rb` add (reusing the category/unit creation pattern; refactor the category+scope+unit block out of `create_core_emission!` into private helpers `create_core_category!`/`create_core_unit!` and reuse them — keep existing factory signatures working):

```ruby
  def create_core_emission_factor!(identifier:, name: "ค่าทดสอบ", value: 1.5,
                                   source: "TGO", unit_title: "kgCO2e/unit", category_id: nil)
    category_id ||= create_core_category!
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.carbon_emission_factors
         (name, source, value_per_unit, unit_title, identifier, carbon_category_id, created_by)
       VALUES (?, ?, ?, ?, ?, ?, 'test') RETURNING id",
      name, source, value, unit_title, identifier, category_id
    ))
    Core::EmissionFactor.find(id)
  end

  def create_core_event_pricing_tier!(min:, max:, price:)
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.event_pricing_tiers
         (min_participants, max_participants, price_per_person, created_by)
       VALUES (?, ?, ?, 'test') RETURNING id", min, max, price
    ))
    Core::EventPricingTier.find(id)
  end

  def create_core_offset_source!(name: "Test Source", name_th: nil)
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.carbon_offset_sources (name, name_th, created_by)
       VALUES (?, ?, 'test') RETURNING id", name, name_th
    ))
    Core::CarbonOffsetSource.find(id)
  end

  def create_core_offset_tier!(source_id:, min:, max:, price:, unit_id: nil)
    unit_id ||= create_core_unit!
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.carbon_offset_pricing_tiers
         (min_emission, max_emission, price_per_emission, unit_id, carbon_offset_source_id, created_by)
       VALUES (?, ?, ?, ?, ?, 'test') RETURNING id", min, max, price, unit_id, source_id
    ))
    Core::CarbonOffsetPricingTier.find(id)
  end

  private

    # carbon_scopes.name CHECK: scope_1|scope_2|scope_3
    def create_core_category!(name_thai: "หมวดทดสอบ", name_eng: "test_category")
      conn = ActiveRecord::Base.connection
      scope_id = conn.select_value(
        "INSERT INTO public.carbon_scopes (name, created_by) VALUES ('scope_1', 'test') RETURNING id"
      )
      conn.select_value(sanitize_sql(
        "INSERT INTO public.carbon_categories (name_thai, name_eng, carbon_scope_id, created_by)
         VALUES (?, ?, ?, 'test') RETURNING id", name_thai, name_eng, scope_id
      ))
    end

    def create_core_unit!(code: "kg", multiplier: 1)
      ActiveRecord::Base.connection.select_value(sanitize_sql(
        "INSERT INTO public.units (code, multiplier, created_by) VALUES (?, ?, 'test') RETURNING id",
        code, multiplier
      ))
    end
```

Refactor `create_core_emission!` to call `create_core_category!`/`create_core_unit!` (same behavior; run the whole suite to prove nothing broke).

- [x] **Step 5: run** target (2 runs PASS) + full suite → 99 runs, 0 failures.
- [x] **Step 6: commit** — `feat: Core models and factories for master-data tables`

---

### Task 2: Emission factor domain — Create/Update/Delete (pure, TDD)

**Files:**
- Create: `app/domain/ports/emission_factor_repository.rb`, `app/domain/master_data/create_emission_factor.rb`, `app/domain/master_data/update_emission_factor.rb`, `app/domain/master_data/delete_emission_factor.rb`
- Test: `test/domain/master_data/emission_factor_test.rb`

- [x] **Step 1: failing test** — `test/domain/master_data/emission_factor_test.rb`

```ruby
require_relative "../../domain_helper"

FakeFactor = Struct.new(:id, :identifier, :name, :description, :source, :value_per_unit,
                        :unit_title, :carbon_category_id, :deleted, :updated_by, :created_by,
                        keyword_init: true)

class FakeFactorRepo
  attr_reader :rows
  def initialize(rows = {}) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def create(attrs, created_by:)
    raise Ports::ValidationFailed, "identifier นี้มีอยู่แล้ว" if @rows.values.any? { |r| r.identifier == attrs[:identifier] && !r.deleted }
    row = FakeFactor.new(id: (@rows.size + 1).to_s, created_by: created_by, deleted: false, **attrs)
    @rows[row.id] = row
  end
  def update(id, attrs, updated_by:)
    row = find(id)
    attrs.each { |k, v| row[k] = v }
    row.updated_by = updated_by
    row
  end
  def soft_delete(id, updated_by:)
    row = find(id)
    row.deleted = true
    row.updated_by = updated_by
    row
  end
end

class EmissionFactorDomainTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @admin = Struct.new(:id, :role, :email_address).new(1, "admin", "ad@pea.co.th")
    @viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    @repo = FakeFactorRepo.new
  end

  def valid_attrs
    { identifier: "ef_test_new", name: "ค่าใหม่", source: "TGO 2026",
      value_per_unit: "2.75", unit_title: "kgCO2e/kg", carbon_category_id: "cat-1" }
  end

  def test_create_validates_and_audits
    result = MasterData::CreateEmissionFactor.call(actor: @admin, attrs: valid_attrs,
                                                   repo: @repo, audit: @audit)
    assert result.success?
    assert_equal 2.75, result.value.value_per_unit
    assert_equal "carbonmice-admin:ad@pea.co.th", result.value.created_by
    assert_equal "master_data.factor_created", @audit_entries.last[:action]
  end

  def test_create_rejects_bad_identifier_and_bad_value
    assert MasterData::CreateEmissionFactor.call(actor: @admin, repo: @repo, audit: @audit,
      attrs: valid_attrs.merge(identifier: "EF BAD!")).failure?
    assert MasterData::CreateEmissionFactor.call(actor: @admin, repo: @repo, audit: @audit,
      attrs: valid_attrs.merge(value_per_unit: "-1")).failure?
    assert MasterData::CreateEmissionFactor.call(actor: @admin, repo: @repo, audit: @audit,
      attrs: valid_attrs.merge(name: "  ")).failure?
    assert_empty @audit_entries
  end

  def test_duplicate_identifier_fails
    MasterData::CreateEmissionFactor.call(actor: @admin, attrs: valid_attrs, repo: @repo, audit: @audit)
    result = MasterData::CreateEmissionFactor.call(actor: @admin, attrs: valid_attrs, repo: @repo, audit: @audit)
    assert result.failure?
    assert_equal "identifier นี้มีอยู่แล้ว", result.error
  end

  def test_update_cannot_touch_identifier
    created = MasterData::CreateEmissionFactor.call(actor: @admin, attrs: valid_attrs,
                                                    repo: @repo, audit: @audit).value
    result = MasterData::UpdateEmissionFactor.call(actor: @admin, id: created.id,
                                                   attrs: { identifier: "ef_other" },
                                                   repo: @repo, audit: @audit)
    assert result.failure?
    assert_equal "ef_test_new", @repo.find(created.id).identifier
  end

  def test_update_edits_value_with_diff_audit
    created = MasterData::CreateEmissionFactor.call(actor: @admin, attrs: valid_attrs,
                                                    repo: @repo, audit: @audit).value
    result = MasterData::UpdateEmissionFactor.call(actor: @admin, id: created.id,
                                                   attrs: { value_per_unit: "3.5" },
                                                   repo: @repo, audit: @audit)
    assert result.success?
    assert_equal({ "value_per_unit" => { "from" => 2.75, "to" => 3.5 } },
                 @audit_entries.last[:changes])
    assert_equal "master_data.factor_updated", @audit_entries.last[:action]
  end

  def test_delete_soft_deletes_with_audit
    created = MasterData::CreateEmissionFactor.call(actor: @admin, attrs: valid_attrs,
                                                    repo: @repo, audit: @audit).value
    result = MasterData::DeleteEmissionFactor.call(actor: @admin, id: created.id,
                                                   repo: @repo, audit: @audit)
    assert result.success?
    assert @repo.find(created.id).deleted
    assert_equal "master_data.factor_deleted", @audit_entries.last[:action]
  end

  def test_viewer_denied_everywhere
    assert MasterData::CreateEmissionFactor.call(actor: @viewer, attrs: valid_attrs,
                                                 repo: @repo, audit: @audit).failure?
    assert MasterData::UpdateEmissionFactor.call(actor: @viewer, id: "1", attrs: { name: "x" },
                                                 repo: @repo, audit: @audit).failure?
    assert MasterData::DeleteEmissionFactor.call(actor: @viewer, id: "1",
                                                 repo: @repo, audit: @audit).failure?
    assert_empty @audit_entries
  end
end
```

- [x] **Step 2: run** `ruby -Itest test/domain/master_data/emission_factor_test.rb` → FAIL.

- [x] **Step 3: implement**

`app/domain/ports/emission_factor_repository.rb`:
```ruby
module Ports
  # Contract:
  #   find(id) -> record | raises Ports::NotFound (unknown/malformed uuid/soft-deleted)
  #   list(search: nil, category_id: nil, page: 1) -> up to PAGE_SIZE+1 records
  #   create(attrs, created_by:) -> record | raises Ports::ValidationFailed (dup identifier, too long)
  #   update(id, attrs, updated_by:) -> record | raises Ports::ValidationFailed
  #   soft_delete(id, updated_by:) -> record
  # Records respond to: id, identifier, name, description, source,
  # value_per_unit, unit_title, carbon_category_id, created_by.
  module EmissionFactorRepository
  end
end
```

`app/domain/master_data/create_emission_factor.rb`:
```ruby
module MasterData
  class CreateEmissionFactor
    REQUIRED = [:identifier, :name, :source, :value_per_unit, :unit_title, :carbon_category_id].freeze
    OPTIONAL = [:description].freeze
    # Matches existing Go identifiers (ef_car_private_gasoline_km ...).
    IDENTIFIER_FORMAT = /\A[a-z0-9_.]+\z/

    def self.call(actor:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym).slice(*(REQUIRED + OPTIONAL))
      missing = REQUIRED.select { |k| attrs[k].to_s.strip.empty? }
      return Result.failure("กรอกข้อมูลไม่ครบ: #{missing.join(", ")}") unless missing.empty?
      return Result.failure("identifier ต้องเป็น a-z, 0-9, _ หรือ . เท่านั้น") unless attrs[:identifier].to_s.match?(IDENTIFIER_FORMAT)

      value = parse_positive_number(attrs[:value_per_unit])
      return Result.failure("ค่า EF ต้องเป็นตัวเลขมากกว่า 0") unless value

      record = repo.create(attrs.merge(value_per_unit: value), created_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.factor_created", actor: actor, target: record,
                   changes: { "identifier" => record.identifier, "value_per_unit" => value })
      Result.success(record)
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end

    def self.parse_positive_number(raw)
      value = Float(raw)
      value.positive? ? value : nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
```

`app/domain/master_data/update_emission_factor.rb`:
```ruby
module MasterData
  class UpdateEmissionFactor
    # identifier is IMMUTABLE: the Go backend looks factors up by it.
    EDITABLE = [:name, :description, :source, :value_per_unit, :unit_title].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      if attrs.key?(:value_per_unit)
        value = CreateEmissionFactor.parse_positive_number(attrs[:value_per_unit])
        return Result.failure("ค่า EF ต้องเป็นตัวเลขมากกว่า 0") unless value
        attrs[:value_per_unit] = value
      end

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [k.to_s, before.public_send(k)] }
      record = repo.update(id, attrs, updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) }] }
      audit.record(action: "master_data.factor_updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบค่า EF")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

`app/domain/master_data/delete_emission_factor.rb`:
```ruby
module MasterData
  class DeleteEmissionFactor
    def self.call(actor:, id:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      record = repo.soft_delete(id, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.factor_deleted", actor: actor, target: record,
                   changes: { "identifier" => record.identifier })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบค่า EF")
    end
  end
end
```

- [x] **Step 4: run** → 7 runs PASS standalone; full suite green (count +7 under rails runner).
- [x] **Step 5: commit** — `feat: emission factor create/update/delete domain with immutable identifier`

---

### Task 3: Emission factor adapter (TDD)

**Files:**
- Create: `app/adapters/persistence/ar_emission_factor_repository.rb`
- Test: `test/adapters/ar_emission_factor_repository_test.rb`

- [x] **Step 1: failing test**

```ruby
require "test_helper"

class ArEmissionFactorRepositoryTest < ActiveSupport::TestCase
  setup { @repo = Persistence::ArEmissionFactorRepository.new }

  test "create persists with stamp and duplicate identifier maps to ValidationFailed" do
    category_id = create_core_emission_factor!(identifier: "ef_seed").carbon_category_id
    record = @repo.create(
      { identifier: "ef_brand_new", name: "ใหม่", source: "TGO", value_per_unit: 1.25,
        unit_title: "kgCO2e/kg", carbon_category_id: category_id },
      created_by: "carbonmice-admin:sa@pea.co.th"
    )
    assert_equal "carbonmice-admin:sa@pea.co.th", record.reload.created_by

    err = assert_raises(Ports::ValidationFailed) do
      @repo.create(
        { identifier: "ef_brand_new", name: "ซ้ำ", source: "TGO", value_per_unit: 1.0,
          unit_title: "kgCO2e/kg", carbon_category_id: category_id },
        created_by: "carbonmice-admin:sa@pea.co.th"
      )
    end
    assert_match "identifier", err.message
  end

  test "list searches identifier and name, filters by category" do
    f1 = create_core_emission_factor!(identifier: "ef_car_test", name: "รถยนต์ทดสอบ")
    create_core_emission_factor!(identifier: "ef_food_test", name: "อาหารทดสอบ")
    assert_equal 1, @repo.list(search: "ef_car").size
    assert_equal 1, @repo.list(search: "อาหาร").size
    assert_equal 1, @repo.list(category_id: f1.carbon_category_id).size
  end

  test "update and soft_delete stamp updated_by; deleted factors vanish" do
    f = create_core_emission_factor!(identifier: "ef_gone")
    @repo.update(f.id, { value_per_unit: 9.99 }, updated_by: "carbonmice-admin:sa@pea.co.th")
    assert_equal 9.99, f.reload.value_per_unit.to_f

    @repo.soft_delete(f.id, updated_by: "carbonmice-admin:sa@pea.co.th")
    assert f.reload.deleted_at.present?
    assert_raises(Ports::NotFound) { @repo.find(f.id) }
    assert_equal 0, @repo.list(search: "ef_gone").size
  end
end
```

- [x] **Step 2: run** → FAIL.

- [x] **Step 3: implement**

```ruby
module Persistence
  class ArEmissionFactorRepository
    PAGE_SIZE = 25

    def find(id)
      Core::EmissionFactor.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(search: nil, category_id: nil, page: 1)
      scope = Core::EmissionFactor.kept.includes(:carbon_category).order(:identifier)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("identifier ILIKE :q OR name ILIKE :q", q: q)
      end
      scope = scope.where(carbon_category_id: category_id) if category_id.present?
      page = [page.to_i, 1].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def create(attrs, created_by:)
      Core::EmissionFactor.create!(**attrs, created_by: created_by)
    rescue ActiveRecord::RecordNotUnique
      raise Ports::ValidationFailed, "identifier นี้มีอยู่แล้ว"
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation => e
      raise Ports::ValidationFailed, e.message
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def soft_delete(id, updated_by:)
      record = find(id)
      record.update!(deleted_at: Time.current, updated_by: updated_by)
      record
    end
  end
end
```

- [x] **Step 4: run** target 3 runs PASS; full suite green.
- [x] **Step 5: commit** — `feat: emission factor adapter with create/soft-delete and dup mapping`

---

### Task 4: Emission factors web (index/new/edit/delete)

**Files:**
- Create: `app/controllers/emission_factors_controller.rb`, `app/views/emission_factors/index.html.erb`, `app/views/emission_factors/new.html.erb`, `app/views/emission_factors/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/emission_factors_controller_test.rb`

- [x] **Step 1: failing test**

```ruby
require "test_helper"

class EmissionFactorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists and searches factors with the Go-restart warning" do
    login(@superadmin)
    create_core_emission_factor!(identifier: "ef_visible", name: "มองเห็น")
    get emission_factors_path
    assert_response :success
    assert_select "td", text: "ef_visible"
    assert_match "ระบบหลัก", response.body   # restart warning banner
    get emission_factors_path, params: { search: "ไม่มีทาง" }
    assert_select "td", text: "ef_visible", count: 0
  end

  test "creates, edits and deletes a factor with audit entries" do
    login(@superadmin)
    category_id = create_core_emission_factor!(identifier: "ef_for_cat").carbon_category_id

    assert_difference -> { AuditLog.where(action: "master_data.factor_created").count } => 1 do
      post emission_factors_path, params: { emission_factor: {
        identifier: "ef_created_via_web", name: "เว็บ", source: "TGO", value_per_unit: "1.5",
        unit_title: "kgCO2e/kg", carbon_category_id: category_id } }
    end
    assert_redirected_to emission_factors_path
    factor = Core::EmissionFactor.find_by!(identifier: "ef_created_via_web")

    get edit_emission_factor_path(factor.id)
    assert_response :success
    assert_select "input[name='emission_factor[identifier]'][disabled]"

    assert_difference -> { AuditLog.where(action: "master_data.factor_updated").count } => 1 do
      patch emission_factor_path(factor.id), params: { emission_factor: { value_per_unit: "2.0" } }
    end
    assert_equal 2.0, factor.reload.value_per_unit.to_f

    assert_difference -> { AuditLog.where(action: "master_data.factor_deleted").count } => 1 do
      delete emission_factor_path(factor.id)
    end
    assert factor.reload.deleted_at.present?
  end

  test "viewer reads but cannot write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    f = create_core_emission_factor!(identifier: "ef_ro")
    get emission_factors_path
    assert_response :success
    patch emission_factor_path(f.id), params: { emission_factor: { value_per_unit: "9" } }
    assert_redirected_to root_path
    assert_equal 1.5, f.reload.value_per_unit.to_f
  end
end
```

- [x] **Step 2: run** → FAIL (routes).

- [x] **Step 3: implement**

`config/routes.rb` — add: `resources :emission_factors, only: %i[index new create edit update destroy]`

`app/controllers/emission_factors_controller.rb`:
```ruby
class EmissionFactorsController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, except: :index

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    rows = repo.list(search: params[:search].presence,
                     category_id: params[:category_id].presence, page: page).to_a
    @has_next = rows.size > Persistence::ArEmissionFactorRepository::PAGE_SIZE
    @factors = rows.first(Persistence::ArEmissionFactorRepository::PAGE_SIZE)
    @page = page
    @categories = Core::CarbonCategory.kept.order(:name_eng)
  end

  def new
    @categories = Core::CarbonCategory.kept.order(:name_eng)
  end

  def create
    result = MasterData::CreateEmissionFactor.call(actor: current_admin, repo: repo, audit: audit,
                                                   attrs: factor_params.to_h.symbolize_keys)
    if result.success?
      redirect_to emission_factors_path, notice: "สร้างค่า EF แล้ว"
    else
      redirect_to new_emission_factor_path, alert: result.error
    end
  end

  def edit
    @factor = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to emission_factors_path, alert: "ไม่พบค่า EF"
  end

  def update
    result = MasterData::UpdateEmissionFactor.call(actor: current_admin, id: params[:id],
                                                   repo: repo, audit: audit,
                                                   attrs: update_params.to_h.symbolize_keys)
    if result.success?
      redirect_to emission_factors_path, notice: "บันทึกการแก้ไขแล้ว"
    else
      redirect_to edit_emission_factor_path(params[:id]), alert: result.error
    end
  end

  def destroy
    result = MasterData::DeleteEmissionFactor.call(actor: current_admin, id: params[:id],
                                                   repo: repo, audit: audit)
    if result.success?
      redirect_to emission_factors_path, notice: "ลบค่า EF แล้ว (soft delete)"
    else
      redirect_to emission_factors_path, alert: result.error
    end
  end

  private
    def factor_params = params.require(:emission_factor)
                              .permit(:identifier, :name, :description, :source,
                                      :value_per_unit, :unit_title, :carbon_category_id)
    def update_params = params.require(:emission_factor)
                              .permit(:name, :description, :source, :value_per_unit, :unit_title)
    def repo = Persistence::ArEmissionFactorRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
```

`app/views/emission_factors/index.html.erb`:
```erb
<div class="flex items-center justify-between">
  <h1 class="text-2xl font-bold text-ink">ค่าการปล่อยคาร์บอน (EF)</h1>
  <% if can?(:manage_master_data) %>
    <%= link_to "เพิ่มค่า EF", new_emission_factor_path,
          class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark" %>
  <% end %>
</div>

<p class="mt-3 max-w-3xl rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-800">
  การแก้ไขมีผลกับการคำนวณทั่วไปทันที ยกเว้นหมวดของแจก/อุปกรณ์อีเว้นท์
  (event items / giveaways) ซึ่งระบบหลักแคชไว้ตอนเริ่มทำงาน — ต้อง restart ระบบหลักจึงจะมีผล
</p>

<%= form_with url: emission_factors_path, method: :get, class: "mt-4 flex flex-wrap items-end gap-3" do |f| %>
  <div>
    <%= f.label :search, "ค้นหา", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.text_field :search, value: params[:search], placeholder: "identifier หรือชื่อ",
          class: "w-72 rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <div>
    <%= f.label :category_id, "หมวด", class: "mb-1 block text-sm font-medium text-ink" %>
    <%= f.select :category_id,
          [["ทั้งหมด", ""]] + @categories.map { |c| ["#{c.name_thai} (#{c.name_eng})", c.id] },
          { selected: params[:category_id] }, class: "rounded-lg border border-gray-300 px-3 py-2" %>
  </div>
  <%= f.submit "กรอง", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>

<table class="mt-6 w-full rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">identifier</th>
      <th class="px-4 py-3">ชื่อ</th>
      <th class="px-4 py-3">ค่า</th>
      <th class="px-4 py-3">หน่วย</th>
      <th class="px-4 py-3">หมวด</th>
      <th class="px-4 py-3"></th>
    </tr>
  </thead>
  <tbody>
    <% @factors.each do |f| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3 font-mono text-xs"><%= f.identifier %></td>
        <td class="px-4 py-3 font-medium text-ink"><%= f.name %></td>
        <td class="px-4 py-3"><%= f.value_per_unit %></td>
        <td class="px-4 py-3"><%= f.unit_title %></td>
        <td class="px-4 py-3"><%= f.carbon_category&.name_thai %></td>
        <td class="px-4 py-3 text-right whitespace-nowrap">
          <% if can?(:manage_master_data) %>
            <%= link_to "แก้ไข", edit_emission_factor_path(f.id), class: "text-primary" %>
            <%= button_to "ลบ", emission_factor_path(f.id), method: :delete,
                  form: { data: { turbo_confirm: "ลบค่า #{f.identifier}? (soft delete)" }, class: "inline" },
                  class: "ml-3 cursor-pointer text-danger" %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<div class="mt-4 flex items-center gap-3">
  <% if @page > 1 %>
    <%= link_to "← ก่อนหน้า", emission_factors_path(search: params[:search], category_id: params[:category_id], page: @page - 1), class: "text-primary" %>
  <% end %>
  <span class="text-sm text-body/60">หน้า <%= @page %></span>
  <% if @has_next %>
    <%= link_to "ถัดไป →", emission_factors_path(search: params[:search], category_id: params[:category_id], page: @page + 1), class: "text-primary" %>
  <% end %>
</div>
```

`app/views/emission_factors/new.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">เพิ่มค่า EF</h1>

<%= form_with url: emission_factors_path, scope: :emission_factor, class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :identifier, "identifier (a-z, 0-9, _, . — แก้ไขภายหลังไม่ได้)", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :identifier, required: true, maxlength: 255, pattern: "[a-z0-9_.]+",
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5 font-mono" %>
  </div>
  <div>
    <%= f.label :name, "ชื่อ", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name, required: true, maxlength: 255, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :description, "คำอธิบาย", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_area :description, rows: 2, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :source, "แหล่งอ้างอิง", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :source, required: true, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :value_per_unit, "ค่า (ต่อหน่วย)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :value_per_unit, required: true, step: "any", min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :unit_title, "หน่วย (เช่น kgCO2e/kg)", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :unit_title, required: true, maxlength: 255, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :carbon_category_id, "หมวด", class: "mb-1 block font-medium text-ink" %>
    <%= f.select :carbon_category_id,
          @categories.map { |c| ["#{c.name_thai} (#{c.name_eng})", c.id] },
          {}, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "สร้าง", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

`app/views/emission_factors/edit.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">แก้ไขค่า EF: <span class="font-mono"><%= @factor.identifier %></span></h1>

<%= form_with url: emission_factor_path(@factor.id), method: :patch, scope: :emission_factor,
      class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :identifier, "identifier (ระบบหลักใช้ค้นหา — แก้ไขไม่ได้)", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :identifier, value: @factor.identifier, disabled: true,
          class: "w-full rounded-lg border border-gray-200 bg-gray-50 px-4 py-2.5 font-mono text-body/60" %>
  </div>
  <div>
    <%= f.label :name, "ชื่อ", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name, value: @factor.name, maxlength: 255, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :description, "คำอธิบาย", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_area :description, value: @factor.description, rows: 2, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :source, "แหล่งอ้างอิง", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :source, value: @factor.source, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :value_per_unit, "ค่า (ต่อหน่วย)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :value_per_unit, value: @factor.value_per_unit, step: "any", min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :unit_title, "หน่วย", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :unit_title, value: @factor.unit_title, maxlength: 255, class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

- [x] **Step 4: run** target 3 runs PASS; full suite green.
- [x] **Step 5: commit** — `feat: emission factor management UI with cache-warning banner`

---

### Task 5: Pricing tiers — domain + adapters (TDD)

**Files:**
- Create: `app/domain/ports/pricing_tier_repositories.rb` (NOTE: single file `ports/pricing_tier_repositories.rb` defining only ONE module `Ports::PricingTierRepositories` documenting BOTH contracts — Zeitwerk needs file↔constant match), `app/domain/master_data/tier_bounds.rb`, `app/domain/master_data/update_event_pricing_tier.rb`, `app/domain/master_data/update_offset_pricing_tier.rb`, `app/adapters/persistence/ar_event_pricing_tier_repository.rb`, `app/adapters/persistence/ar_offset_pricing_tier_repository.rb`
- Test: `test/domain/master_data/pricing_tiers_test.rb`, `test/adapters/ar_pricing_tier_repositories_test.rb`

- [x] **Step 1: failing domain test** — `test/domain/master_data/pricing_tiers_test.rb`

```ruby
require_relative "../../domain_helper"

FakeTier = Struct.new(:id, :min_participants, :max_participants, :price_per_person,
                      :min_emission, :max_emission, :price_per_emission,
                      :carbon_offset_source_id, :updated_by, keyword_init: true)

class FakeTierRepo
  attr_reader :rows
  def initialize(rows) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def list(source_id: nil)
    rows = @rows.values
    rows = rows.select { |r| r.carbon_offset_source_id == source_id } if source_id
    rows
  end
  def update(id, attrs, updated_by:)
    row = find(id)
    attrs.each { |k, v| row[k] = v }
    row.updated_by = updated_by
    row
  end
end

class PricingTiersDomainTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @admin = Struct.new(:id, :role, :email_address).new(1, "admin", "ad@pea.co.th")
  end

  def event_repo
    FakeTierRepo.new(
      "t1" => FakeTier.new(id: "t1", min_participants: 1, max_participants: 1000, price_per_person: 5.0),
      "t2" => FakeTier.new(id: "t2", min_participants: 1001, max_participants: 2000, price_per_person: 4.0)
    )
  end

  def test_event_tier_price_update_audits
    repo = event_repo
    result = MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
                                                     attrs: { price_per_person: "6.5" },
                                                     repo: repo, audit: @audit)
    assert result.success?
    assert_equal 6.5, repo.find("t1").price_per_person
    assert_equal "master_data.event_tier_updated", @audit_entries.last[:action]
  end

  def test_event_tier_overlap_is_rejected
    repo = event_repo
    result = MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
                                                     attrs: { max_participants: "1500" },
                                                     repo: repo, audit: @audit)
    assert result.failure?
    assert_equal 1000, repo.find("t1").max_participants
  end

  def test_event_tier_bounds_validated
    repo = event_repo
    assert MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
      attrs: { min_participants: "-5" }, repo: repo, audit: @audit).failure?
    assert MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
      attrs: { min_participants: "500", max_participants: "100" }, repo: repo, audit: @audit).failure?
    assert MasterData::UpdateEventPricingTier.call(actor: @admin, id: "t1",
      attrs: { price_per_person: "free" }, repo: repo, audit: @audit).failure?
  end

  def test_offset_tier_overlap_scoped_to_source
    repo = FakeTierRepo.new(
      "o1" => FakeTier.new(id: "o1", min_emission: 0, max_emission: 100,
                           price_per_emission: 100.0, carbon_offset_source_id: "s1"),
      "o2" => FakeTier.new(id: "o2", min_emission: 0, max_emission: 100,
                           price_per_emission: 90.0, carbon_offset_source_id: "s2")
    )
    # overlapping range exists in s2 but NOT in s1 → extending o1 within s1 only checks s1
    result = MasterData::UpdateOffsetPricingTier.call(actor: @admin, id: "o1",
                                                      attrs: { max_emission: "150" },
                                                      repo: repo, audit: @audit)
    assert result.success?
    assert_equal 150, repo.find("o1").max_emission
    assert_equal "master_data.offset_tier_updated", @audit_entries.last[:action]
  end

  def test_viewer_denied
    viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    assert MasterData::UpdateEventPricingTier.call(actor: viewer, id: "t1",
      attrs: { price_per_person: "1" }, repo: event_repo, audit: @audit).failure?
    assert_empty @audit_entries
  end
end
```

- [x] **Step 2: run** → FAIL.

- [x] **Step 3: implement**

`app/domain/ports/pricing_tier_repositories.rb`:
```ruby
module Ports
  # Two adapters share this contract shape (event tiers have no source scope):
  #   find(id) -> record | raises Ports::NotFound
  #   list(source_id: nil) -> all live tiers (event tiers ignore source_id)
  #   update(id, attrs, updated_by:) -> record
  # Event tier records: min_participants, max_participants (nil = open), price_per_person.
  # Offset tier records: min_emission, max_emission (nil = open), price_per_emission,
  # carbon_offset_source_id.
  module PricingTierRepositories
  end
end
```

`app/domain/master_data/update_event_pricing_tier.rb`:
```ruby
module MasterData
  class UpdateEventPricingTier
    EDITABLE = [:min_participants, :max_participants, :price_per_person].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      before = repo.find(id)
      parsed = TierBounds.parse(attrs,
                                min_key: :min_participants, max_key: :max_participants,
                                price_key: :price_per_person,
                                current_min: before.min_participants,
                                current_max: before.max_participants)
      return Result.failure(parsed) if parsed.is_a?(String)

      others = repo.list.reject { |t| t.id == before.id }
      if TierBounds.overlaps?(parsed[:min], parsed[:max], others,
                              min_key: :min_participants, max_key: :max_participants)
        return Result.failure("ช่วงผู้เข้าร่วมทับซ้อนกับระดับราคาอื่น")
      end

      snapshot = attrs.keys.to_h { |k| [k.to_s, before.public_send(k)] }
      record = repo.update(id, parsed[:attrs], updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) }] }
      audit.record(action: "master_data.event_tier_updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบระดับราคา")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

`app/domain/master_data/update_offset_pricing_tier.rb`:
```ruby
module MasterData
  class UpdateOffsetPricingTier
    EDITABLE = [:min_emission, :max_emission, :price_per_emission].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      before = repo.find(id)
      parsed = TierBounds.parse(attrs,
                                min_key: :min_emission, max_key: :max_emission,
                                price_key: :price_per_emission,
                                current_min: before.min_emission,
                                current_max: before.max_emission)
      return Result.failure(parsed) if parsed.is_a?(String)

      others = repo.list(source_id: before.carbon_offset_source_id).reject { |t| t.id == before.id }
      if TierBounds.overlaps?(parsed[:min], parsed[:max], others,
                              min_key: :min_emission, max_key: :max_emission)
        return Result.failure("ช่วงปริมาณคาร์บอนทับซ้อนกับระดับราคาอื่นในแหล่งเดียวกัน")
      end

      snapshot = attrs.keys.to_h { |k| [k.to_s, before.public_send(k)] }
      record = repo.update(id, parsed[:attrs], updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) }] }
      audit.record(action: "master_data.offset_tier_updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบระดับราคา")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

`app/domain/master_data/tier_bounds.rb` (shared parsing/overlap helper — add to the Create/Update files list):
```ruby
module MasterData
  # Shared numeric parsing + range-overlap logic for both tier types.
  module TierBounds
    INT_MAX = 2_147_483_647

    # Returns { attrs:, min:, max: } or an error String.
    def self.parse(attrs, min_key:, max_key:, price_key:, current_min:, current_max:)
      out = attrs.dup

      if attrs.key?(min_key)
        min = parse_int(attrs[min_key])
        return "ค่าต่ำสุดต้องเป็นจำนวนเต็ม 0 ถึง #{INT_MAX}" if min.nil? || min.negative? || min > INT_MAX
        out[min_key] = min
      else
        min = current_min
      end

      if attrs.key?(max_key)
        raw = attrs[max_key].to_s.strip
        if raw.empty?
          max = nil
        else
          max = parse_int(raw)
          return "ค่าสูงสุดต้องเป็นจำนวนเต็ม หรือเว้นว่าง (ไม่จำกัด)" if max.nil? || max > INT_MAX
        end
        out[max_key] = max
      else
        max = current_max
      end

      return "ค่าสูงสุดต้องมากกว่าค่าต่ำสุด" if max && max <= min

      if attrs.key?(price_key)
        price = parse_price(attrs[price_key])
        return "ราคาต้องเป็นตัวเลขตั้งแต่ 0 ขึ้นไป" if price.nil?
        out[price_key] = price
      end

      { attrs: out, min: min, max: max }
    end

    def self.overlaps?(min, max, others, min_key:, max_key:)
      hi = max || Float::INFINITY
      others.any? do |o|
        o_hi = o.public_send(max_key) || Float::INFINITY
        min <= o_hi && hi >= o.public_send(min_key)
      end
    end

    def self.parse_int(raw)
      Integer(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def self.parse_price(raw)
      value = Float(raw)
      value.negative? ? nil : value
    rescue ArgumentError, TypeError
      nil
    end
  end
end
```

Adapters `app/adapters/persistence/ar_event_pricing_tier_repository.rb`:
```ruby
module Persistence
  class ArEventPricingTierRepository
    def find(id)
      Core::EventPricingTier.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(source_id: nil)
      Core::EventPricingTier.kept.order(:min_participants).to_a
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::StatementInvalid => e
      # DB CHECK constraints (max > 0 AND >= min) are the last line of defense.
      raise Ports::ValidationFailed, "ค่าขัดกับเงื่อนไขของฐานข้อมูล"
    end
  end
end
```

`app/adapters/persistence/ar_offset_pricing_tier_repository.rb`:
```ruby
module Persistence
  class ArOffsetPricingTierRepository
    def find(id)
      Core::CarbonOffsetPricingTier.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(source_id: nil)
      scope = Core::CarbonOffsetPricingTier.kept.order(:min_emission)
      scope = scope.where(carbon_offset_source_id: source_id) if source_id
      scope.to_a
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::StatementInvalid
      raise Ports::ValidationFailed, "ค่าขัดกับเงื่อนไขของฐานข้อมูล"
    end
  end
end
```

- [x] **Step 4: failing adapter test** — `test/adapters/ar_pricing_tier_repositories_test.rb`

```ruby
require "test_helper"

class ArPricingTierRepositoriesTest < ActiveSupport::TestCase
  test "event tier update stamps and lists ordered" do
    repo = Persistence::ArEventPricingTierRepository.new
    t1 = create_core_event_pricing_tier!(min: 1, max: 100, price: 5.0)
    create_core_event_pricing_tier!(min: 101, max: 200, price: 4.0)
    repo.update(t1.id, { price_per_person: 6.0 }, updated_by: "carbonmice-admin:sa@pea.co.th")
    assert_equal 6.0, t1.reload.price_per_person.to_f
    assert_equal "carbonmice-admin:sa@pea.co.th", t1.reload.updated_by
    assert_equal [1, 101], repo.list.map(&:min_participants)
  end

  test "offset tier list scopes by source" do
    repo = Persistence::ArOffsetPricingTierRepository.new
    s1 = create_core_offset_source!(name: "S1")
    s2 = create_core_offset_source!(name: "S2")
    create_core_offset_tier!(source_id: s1.id, min: 0, max: 100, price: 99.0)
    create_core_offset_tier!(source_id: s2.id, min: 0, max: 100, price: 88.0)
    assert_equal 1, repo.list(source_id: s1.id).size
    assert_equal 2, repo.list.size
  end
end
```

- [x] **Step 5: run** domain (6 runs) + adapter (2 runs) PASS; full suite green.
- [x] **Step 6: commit** — `feat: pricing tier updates with bounds and overlap validation`

---

### Task 6: Pricing tiers web

**Files:**
- Create: `app/controllers/pricing_tiers_controller.rb`, `app/views/pricing_tiers/index.html.erb`, `app/views/pricing_tiers/edit_event.html.erb`, `app/views/pricing_tiers/edit_offset.html.erb`
- Modify: `config/routes.rb`
- Test: `test/controllers/pricing_tiers_controller_test.rb`

- [x] **Step 1: failing test**

```ruby
require "test_helper"

class PricingTiersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "index shows both tier tables grouped" do
    login(@superadmin)
    create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    src = create_core_offset_source!(name: "TGO-X", name_th: "ทีจีโอเอ็กซ์")
    create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.0)
    get pricing_tiers_path
    assert_response :success
    assert_select "td", text: "5.0"
    assert_match "ทีจีโอเอ็กซ์", response.body
  end

  test "updates an event tier price with audit" do
    login(@superadmin)
    tier = create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    get edit_event_pricing_tier_path(tier.id)
    assert_response :success
    assert_difference -> { AuditLog.where(action: "master_data.event_tier_updated").count } => 1 do
      patch event_pricing_tier_path(tier.id), params: { tier: { price_per_person: "7.25" } }
    end
    assert_equal 7.25, tier.reload.price_per_person.to_f
  end

  test "updates an offset tier with overlap rejection" do
    login(@superadmin)
    src = create_core_offset_source!(name: "S")
    a = create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.0)
    create_core_offset_tier!(source_id: src.id, min: 101, max: 200, price: 89.0)
    patch offset_pricing_tier_path(a.id), params: { tier: { max_emission: "150" } }
    assert_redirected_to edit_offset_pricing_tier_path(a.id)
    assert_equal 100, a.reload.max_emission
  end

  test "viewer reads index but cannot write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    tier = create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    get pricing_tiers_path
    assert_response :success
    patch event_pricing_tier_path(tier.id), params: { tier: { price_per_person: "1" } }
    assert_redirected_to root_path
    assert_equal 5.0, tier.reload.price_per_person.to_f
  end
end
```

- [x] **Step 2: run** → FAIL (routes).

- [x] **Step 3: implement**

`config/routes.rb` — add:
```ruby
  get "pricing_tiers", to: "pricing_tiers#index", as: :pricing_tiers
  get "pricing_tiers/event/:id/edit", to: "pricing_tiers#edit_event", as: :edit_event_pricing_tier
  patch "pricing_tiers/event/:id", to: "pricing_tiers#update_event", as: :event_pricing_tier
  get "pricing_tiers/offset/:id/edit", to: "pricing_tiers#edit_offset", as: :edit_offset_pricing_tier
  patch "pricing_tiers/offset/:id", to: "pricing_tiers#update_offset", as: :offset_pricing_tier
```

`app/controllers/pricing_tiers_controller.rb`:
```ruby
class PricingTiersController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, except: :index

  def index
    @event_tiers = event_repo.list
    @offset_sources = Core::CarbonOffsetSource.kept.order(:name)
    @offset_tiers_by_source = offset_repo.list.group_by(&:carbon_offset_source_id)
  end

  def edit_event
    @tier = event_repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to pricing_tiers_path, alert: "ไม่พบระดับราคา"
  end

  def update_event
    result = MasterData::UpdateEventPricingTier.call(actor: current_admin, id: params[:id],
                                                     attrs: tier_params(:min_participants, :max_participants, :price_per_person),
                                                     repo: event_repo, audit: audit)
    if result.success?
      redirect_to pricing_tiers_path, notice: "บันทึกระดับราคาแล้ว"
    else
      redirect_to edit_event_pricing_tier_path(params[:id]), alert: result.error
    end
  end

  def edit_offset
    @tier = offset_repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to pricing_tiers_path, alert: "ไม่พบระดับราคา"
  end

  def update_offset
    result = MasterData::UpdateOffsetPricingTier.call(actor: current_admin, id: params[:id],
                                                      attrs: tier_params(:min_emission, :max_emission, :price_per_emission),
                                                      repo: offset_repo, audit: audit)
    if result.success?
      redirect_to pricing_tiers_path, notice: "บันทึกระดับราคาแล้ว"
    else
      redirect_to edit_offset_pricing_tier_path(params[:id]), alert: result.error
    end
  end

  private
    def tier_params(*keys) = params.require(:tier).permit(*keys).to_h.symbolize_keys
    def event_repo = Persistence::ArEventPricingTierRepository.new
    def offset_repo = Persistence::ArOffsetPricingTierRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
```

`app/views/pricing_tiers/index.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">ระดับราคา</h1>

<h2 class="mt-6 text-lg font-semibold text-ink">ค่าบริการต่อผู้เข้าร่วม (event pricing)</h2>
<table class="mt-3 w-full max-w-3xl rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">ผู้เข้าร่วม (ต่ำสุด)</th>
      <th class="px-4 py-3">ผู้เข้าร่วม (สูงสุด)</th>
      <th class="px-4 py-3">ราคา/คน (บาท)</th>
      <th class="px-4 py-3"></th>
    </tr>
  </thead>
  <tbody>
    <% @event_tiers.each do |t| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3"><%= t.min_participants %></td>
        <td class="px-4 py-3"><%= t.max_participants || "ไม่จำกัด" %></td>
        <td class="px-4 py-3 font-medium text-ink"><%= t.price_per_person %></td>
        <td class="px-4 py-3 text-right">
          <% if can?(:manage_master_data) %>
            <%= link_to "แก้ไข", edit_event_pricing_tier_path(t.id), class: "text-primary" %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<h2 class="mt-8 text-lg font-semibold text-ink">ราคาชดเชยคาร์บอน (offset pricing)</h2>
<% @offset_sources.each do |source| %>
  <h3 class="mt-4 font-medium text-ink"><%= source.name_th.presence || source.name %></h3>
  <table class="mt-2 w-full max-w-3xl rounded-xl bg-white shadow-sm text-sm">
    <thead>
      <tr class="border-b border-gray-200 text-left text-body/60">
        <th class="px-4 py-3">ปริมาณ (ต่ำสุด)</th>
        <th class="px-4 py-3">ปริมาณ (สูงสุด)</th>
        <th class="px-4 py-3">ราคา/หน่วย (บาท)</th>
        <th class="px-4 py-3"></th>
      </tr>
    </thead>
    <tbody>
      <% (@offset_tiers_by_source[source.id] || []).each do |t| %>
        <tr class="border-b border-gray-100">
          <td class="px-4 py-3"><%= t.min_emission %></td>
          <td class="px-4 py-3"><%= t.max_emission || "ไม่จำกัด" %></td>
          <td class="px-4 py-3 font-medium text-ink"><%= t.price_per_emission %></td>
          <td class="px-4 py-3 text-right">
            <% if can?(:manage_master_data) %>
              <%= link_to "แก้ไข", edit_offset_pricing_tier_path(t.id), class: "text-primary" %>
            <% end %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

`app/views/pricing_tiers/edit_event.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">แก้ไขระดับราคา (ผู้เข้าร่วม)</h1>

<%= form_with url: event_pricing_tier_path(@tier.id), method: :patch, scope: :tier,
      class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :min_participants, "ผู้เข้าร่วมต่ำสุด", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :min_participants, value: @tier.min_participants, min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :max_participants, "ผู้เข้าร่วมสูงสุด (เว้นว่าง = ไม่จำกัด)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :max_participants, value: @tier.max_participants, min: 1,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :price_per_person, "ราคา/คน (บาท)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :price_per_person, value: @tier.price_per_person, step: "0.01", min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

`app/views/pricing_tiers/edit_offset.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">แก้ไขระดับราคา (ชดเชยคาร์บอน)</h1>

<%= form_with url: offset_pricing_tier_path(@tier.id), method: :patch, scope: :tier,
      class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :min_emission, "ปริมาณต่ำสุด", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :min_emission, value: @tier.min_emission, min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :max_emission, "ปริมาณสูงสุด (เว้นว่าง = ไม่จำกัด)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :max_emission, value: @tier.max_emission, min: 1,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :price_per_emission, "ราคา/หน่วย (บาท)", class: "mb-1 block font-medium text-ink" %>
    <%= f.number_field :price_per_emission, value: @tier.price_per_emission, step: "0.01", min: 0,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

- [x] **Step 4: run** target 4 runs PASS; full suite green.
- [x] **Step 5: commit** — `feat: pricing tier management UI`

---

### Task 7: Categories & units page (name_thai rename only)

**Files:**
- Create: `app/domain/ports/category_repository.rb`, `app/domain/master_data/rename_category.rb`, `app/adapters/persistence/ar_category_repository.rb`, `app/controllers/categories_controller.rb`, `app/views/categories/index.html.erb`, `app/views/categories/edit.html.erb`
- Modify: `config/routes.rb`
- Test: `test/domain/master_data/rename_category_test.rb`, `test/controllers/categories_controller_test.rb`

- [x] **Step 1: failing domain test** — `test/domain/master_data/rename_category_test.rb`

```ruby
require_relative "../../domain_helper"

FakeCategory = Struct.new(:id, :name_thai, :name_eng, :updated_by, keyword_init: true)

class FakeCategoryRepo
  attr_reader :rows
  def initialize(rows) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def update_name_thai(id, name_thai, updated_by:)
    row = find(id)
    row.name_thai = name_thai
    row.updated_by = updated_by
    row
  end
end

class RenameCategoryTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @admin = Struct.new(:id, :role, :email_address).new(1, "admin", "ad@pea.co.th")
    @repo = FakeCategoryRepo.new(
      "c1" => FakeCategory.new(id: "c1", name_thai: "การเดินทาง", name_eng: "travel")
    )
  end

  def test_renames_thai_label_with_audit
    result = MasterData::RenameCategory.call(actor: @admin, id: "c1",
                                             name_thai: "การเดินทางและขนส่ง",
                                             repo: @repo, audit: @audit)
    assert result.success?
    assert_equal "การเดินทางและขนส่ง", @repo.find("c1").name_thai
    assert_equal "master_data.category_renamed", @audit_entries.last[:action]
    assert_equal({ "name_thai" => { "from" => "การเดินทาง", "to" => "การเดินทางและขนส่ง" } },
                 @audit_entries.last[:changes])
  end

  def test_blank_name_rejected
    result = MasterData::RenameCategory.call(actor: @admin, id: "c1", name_thai: "  ",
                                             repo: @repo, audit: @audit)
    assert result.failure?
  end

  def test_viewer_denied
    viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    result = MasterData::RenameCategory.call(actor: viewer, id: "c1", name_thai: "x",
                                             repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end
end
```

- [x] **Step 2: implement domain + port + adapter**

`app/domain/ports/category_repository.rb`:
```ruby
module Ports
  # Contract:
  #   find(id) -> record | raises Ports::NotFound
  #   list -> all live categories
  #   update_name_thai(id, name_thai, updated_by:) -> record
  # name_eng is NEVER updatable: the Go backend matches it as an enum.
  module CategoryRepository
  end
end
```

`app/domain/master_data/rename_category.rb`:
```ruby
module MasterData
  class RenameCategory
    # ONLY the Thai display label is editable. name_eng is a Go enum value.
    def self.call(actor:, id:, name_thai:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      name_thai = name_thai.to_s.strip
      return Result.failure("ชื่อภาษาไทยห้ามว่าง") if name_thai.empty?

      before = repo.find(id)
      from = before.name_thai
      record = repo.update_name_thai(id, name_thai, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.category_renamed", actor: actor, target: record,
                   changes: { "name_thai" => { "from" => from, "to" => name_thai } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบหมวดหมู่")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
```

`app/adapters/persistence/ar_category_repository.rb`:
```ruby
module Persistence
  class ArCategoryRepository
    def find(id)
      Core::CarbonCategory.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list = Core::CarbonCategory.kept.order(:name_eng).to_a

    def update_name_thai(id, name_thai, updated_by:)
      record = find(id)
      record.update!(name_thai: name_thai, updated_by: updated_by)
      record
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    end
  end
end
```

- [x] **Step 3: failing controller test** — `test/controllers/categories_controller_test.rb`

```ruby
require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists categories and units read-only with locked name_eng" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_cat_seed")   # seeds a category + nothing else
    get categories_path
    assert_response :success
    assert_match "test_category", response.body
    assert_match "แก้ไขไม่ได้", response.body   # lock explanation
  end

  test "renames category Thai label with audit; name_eng untouchable" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_cat_seed2")
    category = Core::CarbonCategory.find(f.carbon_category_id)
    assert_difference -> { AuditLog.where(action: "master_data.category_renamed").count } => 1 do
      patch category_path(category.id), params: { category: { name_thai: "ชื่อใหม่", name_eng: "hacked" } }
    end
    category.reload
    assert_equal "ชื่อใหม่", category.name_thai
    assert_equal "test_category", category.name_eng   # strong params drop name_eng
  end

  test "viewer cannot rename" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    f = create_core_emission_factor!(identifier: "ef_cat_seed3")
    category = Core::CarbonCategory.find(f.carbon_category_id)
    patch category_path(category.id), params: { category: { name_thai: "ห้าม" } }
    assert_redirected_to root_path
    assert_equal "หมวดทดสอบ", category.reload.name_thai
  end
end
```

- [x] **Step 4: implement web**

`config/routes.rb` — add: `resources :categories, only: %i[index edit update]`

`app/controllers/categories_controller.rb`:
```ruby
class CategoriesController < ApplicationController
  before_action -> { authorize!(:view_operations) }, only: :index
  before_action -> { authorize!(:manage_master_data) }, only: %i[edit update]

  def index
    @categories = repo.list
    @units = Core::Unit.kept.order(:code)
  end

  def edit
    @category = repo.find(params[:id])
  rescue Ports::NotFound
    redirect_to categories_path, alert: "ไม่พบหมวดหมู่"
  end

  def update
    result = MasterData::RenameCategory.call(actor: current_admin, id: params[:id],
                                             name_thai: params.require(:category)[:name_thai],
                                             repo: repo, audit: audit)
    if result.success?
      redirect_to categories_path, notice: "บันทึกชื่อหมวดแล้ว"
    else
      redirect_to edit_category_path(params[:id]), alert: result.error
    end
  end

  private
    def repo = Persistence::ArCategoryRepository.new
    def audit = Persistence::ArAuditRecorder.new
end
```

`app/views/categories/index.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">หมวดหมู่และหน่วย</h1>
<p class="mt-2 max-w-3xl text-sm text-body/60">
  รหัสภาษาอังกฤษ (name_eng) และรหัสหน่วย (code) เป็นค่าที่ระบบหลักใช้อ้างอิงในโค้ด —
  แก้ไขไม่ได้ แก้ได้เฉพาะชื่อภาษาไทยของหมวด
</p>

<h2 class="mt-6 text-lg font-semibold text-ink">หมวดคาร์บอน</h2>
<table class="mt-3 w-full max-w-3xl rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">ชื่อ (ไทย)</th>
      <th class="px-4 py-3">รหัส (name_eng)</th>
      <th class="px-4 py-3"></th>
    </tr>
  </thead>
  <tbody>
    <% @categories.each do |c| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3 font-medium text-ink"><%= c.name_thai %></td>
        <td class="px-4 py-3 font-mono text-xs"><%= c.name_eng %> 🔒</td>
        <td class="px-4 py-3 text-right">
          <% if can?(:manage_master_data) %>
            <%= link_to "แก้ชื่อไทย", edit_category_path(c.id), class: "text-primary" %>
          <% end %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<h2 class="mt-8 text-lg font-semibold text-ink">หน่วย (อ่านอย่างเดียว)</h2>
<table class="mt-3 w-full max-w-md rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">รหัส</th>
      <th class="px-4 py-3">ตัวคูณ</th>
    </tr>
  </thead>
  <tbody>
    <% @units.each do |u| %>
      <tr class="border-b border-gray-100">
        <td class="px-4 py-3 font-mono text-xs"><%= u.code %> 🔒</td>
        <td class="px-4 py-3"><%= u.multiplier %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

`app/views/categories/edit.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">แก้ชื่อหมวด: <span class="font-mono"><%= @category.name_eng %></span></h1>

<%= form_with url: category_path(@category.id), method: :patch, scope: :category,
      class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :name_thai, "ชื่อภาษาไทย", class: "mb-1 block font-medium text-ink" %>
    <%= f.text_field :name_thai, value: @category.name_thai, required: true, maxlength: 255,
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "บันทึก", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

- [x] **Step 5: run** all new tests PASS; full suite green.
- [x] **Step 6: commit** — `feat: category Thai-label rename with locked Go enum codes`

---

### Task 8: Dashboard

**Files:**
- Create: `app/domain/ports/stats_query.rb`, `app/domain/dashboard/system_summary.rb`, `app/adapters/persistence/ar_stats_query.rb`
- Modify: `app/controllers/home_controller.rb`, `app/views/home/show.html.erb`
- Test: `test/controllers/dashboard_test.rb`

- [x] **Step 1: failing test** — `test/controllers/dashboard_test.rb`

```ruby
require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  def login_as(role)
    admin = AdminUser.create!(email_address: "#{role}@pea.co.th",
                              password: "password-for-tests", name: role.to_s, role: role)
    post session_path, params: { email_address: admin.email_address, password: "password-for-tests" }
    admin
  end

  test "dashboard shows totals and status breakdown" do
    login_as(:superadmin)
    create_core_event!(name_thai: "งาน1", status: "collecting")
    create_core_event!(name_thai: "งาน2", status: "collecting")
    create_core_user!(email: "u@example.com")
    get root_path
    assert_response :success
    assert_match "อีเว้นท์ทั้งหมด", response.body
    assert_select "td", text: "collecting"
    assert_select "td", text: "2"
  end

  test "recent activity is visible to superadmin only" do
    login_as(:superadmin)
    get root_path
    assert_match "กิจกรรมล่าสุด", response.body   # superadmin sees recent audit
    delete session_path

    login_as(:viewer)
    get root_path
    assert_response :success
    refute_match "กิจกรรมล่าสุด", response.body
  end
end
```

- [x] **Step 2: implement**

`app/domain/ports/stats_query.rb`:
```ruby
module Ports
  # Contract:
  #   totals -> { events:, app_users:, package_users:, factors: } (Integers, live rows)
  #   events_by_status -> [{ name_eng:, name_thai:, count: }] catalog-ordered,
  #     zero-count statuses included; statuses present on events but missing
  #     from the catalog are appended with name_thai = nil.
  module StatsQuery
  end
end
```

`app/domain/dashboard/system_summary.rb`:
```ruby
module Dashboard
  class SystemSummary
    def self.call(actor:, stats:)
      return Result.failure("คุณไม่มีสิทธิ์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :view_operations)

      Result.success(totals: stats.totals, by_status: stats.events_by_status)
    end
  end
end
```

`app/adapters/persistence/ar_stats_query.rb`:
```ruby
module Persistence
  class ArStatsQuery
    def totals
      {
        events: Core::Event.kept.count,
        app_users: Core::User.kept.count,
        package_users: Core::User.kept.where(is_package_user: true).count,
        factors: Core::EmissionFactor.kept.count
      }
    end

    def events_by_status
      counts = Core::Event.kept.group(:event_status).count
      catalog = Core::EventStatus.ordered.map do |s|
        { name_eng: s.name_eng, name_thai: s.name_thai, count: counts.delete(s.name_eng) || 0 }
      end
      strays = counts.map { |status, count| { name_eng: status.to_s, name_thai: nil, count: count } }
      catalog + strays
    end
  end
end
```

`app/controllers/home_controller.rb`:
```ruby
class HomeController < ApplicationController
  def show
    result = Dashboard::SystemSummary.call(actor: current_admin, stats: Persistence::ArStatsQuery.new)
    raise ApplicationController::NotAuthorized if result.failure?
    @totals = result.value[:totals]
    @by_status = result.value[:by_status]
    # Audit data is superadmin-only (same gate as the audit page).
    @recent_activity = can?(:view_audit_log) ? AuditLog.order(created_at: :desc).limit(10) : nil
  end
end
```

`app/views/home/show.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">ภาพรวมระบบ</h1>

<div class="mt-6 grid max-w-4xl grid-cols-2 gap-4 lg:grid-cols-4">
  <div class="rounded-xl bg-white p-5 shadow-sm">
    <p class="text-sm text-body/60">อีเว้นท์ทั้งหมด</p>
    <p class="mt-1 text-3xl font-bold text-primary"><%= @totals[:events] %></p>
  </div>
  <div class="rounded-xl bg-white p-5 shadow-sm">
    <p class="text-sm text-body/60">ผู้ใช้งานระบบหลัก</p>
    <p class="mt-1 text-3xl font-bold text-primary"><%= @totals[:app_users] %></p>
  </div>
  <div class="rounded-xl bg-white p-5 shadow-sm">
    <p class="text-sm text-body/60">ผู้ใช้แบบแพ็กเกจ</p>
    <p class="mt-1 text-3xl font-bold text-primary"><%= @totals[:package_users] %></p>
  </div>
  <div class="rounded-xl bg-white p-5 shadow-sm">
    <p class="text-sm text-body/60">ค่า EF ในระบบ</p>
    <p class="mt-1 text-3xl font-bold text-primary"><%= @totals[:factors] %></p>
  </div>
</div>

<h2 class="mt-8 text-lg font-semibold text-ink">อีเว้นท์ตามสถานะ</h2>
<table class="mt-3 w-full max-w-2xl rounded-xl bg-white shadow-sm text-sm">
  <thead>
    <tr class="border-b border-gray-200 text-left text-body/60">
      <th class="px-4 py-3">สถานะ</th>
      <th class="px-4 py-3">รหัส</th>
      <th class="px-4 py-3 text-right">จำนวน</th>
    </tr>
  </thead>
  <tbody>
    <% @by_status.each do |row| %>
      <tr class="border-b border-gray-100 <%= "text-body/40" if row[:count].zero? %>">
        <td class="px-4 py-3"><%= row[:name_thai] || "—" %></td>
        <td class="px-4 py-3"><%= row[:name_eng] %></td>
        <td class="px-4 py-3 text-right font-medium"><%= row[:count] %></td>
      </tr>
    <% end %>
  </tbody>
</table>

<% if @recent_activity %>
  <h2 class="mt-8 text-lg font-semibold text-ink">กิจกรรมล่าสุด</h2>
  <table class="mt-3 w-full max-w-3xl rounded-xl bg-white shadow-sm text-sm">
    <tbody>
      <% @recent_activity.each do |e| %>
        <tr class="border-b border-gray-100">
          <td class="whitespace-nowrap px-4 py-2 text-body/60"><%= e.created_at.in_time_zone.strftime("%d/%m %H:%M") %></td>
          <td class="px-4 py-2"><%= e.actor_email %></td>
          <td class="px-4 py-2 font-medium text-ink"><%= e.action %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <p class="mt-2 text-sm"><%= link_to "ดูบันทึกทั้งหมด →", audit_logs_path, class: "text-primary" %></p>
<% end %>
```

NOTE: the existing home_controller_test asserts nav links — keep those passing. The dashboard reads AuditLog directly for the recent list (same data the superadmin-only audit page exposes; controller gates with can?(:view_audit_log)) — this mirrors the established read-path pattern.

- [x] **Step 3: run** new tests + full suite green (home tests still pass).
- [x] **Step 4: commit** — `feat: system dashboard with status breakdown and recent activity`

---

### Task 9: Admin self-service password change

**Files:**
- Create: `app/controllers/passwords_controller.rb`, `app/views/passwords/edit.html.erb`
- Modify: `config/routes.rb`, `app/views/shared/_sidebar.html.erb`
- Test: `test/controllers/passwords_controller_test.rb`

- [x] **Step 1: failing test**

```ruby
require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email_address: "me@pea.co.th",
                               password: "password-for-tests", name: "ฉัน", role: :admin)
    post session_path, params: { email_address: "me@pea.co.th", password: "password-for-tests" }
  end

  test "changes password with correct current password and audits" do
    get edit_password_path
    assert_response :success
    assert_difference -> { AuditLog.where(action: "auth.password_changed").count } => 1 do
      patch password_path, params: { current_password: "password-for-tests",
                                     password: "a-brand-new-password",
                                     password_confirmation: "a-brand-new-password" }
    end
    assert_redirected_to root_path
    assert AdminUser.authenticate_by(email_address: "me@pea.co.th", password: "a-brand-new-password")
  end

  test "wrong current password is rejected without audit" do
    assert_no_difference -> { AuditLog.count } do
      patch password_path, params: { current_password: "wrong-password!",
                                     password: "a-brand-new-password",
                                     password_confirmation: "a-brand-new-password" }
    end
    assert_redirected_to edit_password_path
    assert AdminUser.authenticate_by(email_address: "me@pea.co.th", password: "password-for-tests")
  end

  test "mismatched confirmation and short password are rejected" do
    patch password_path, params: { current_password: "password-for-tests",
                                   password: "a-brand-new-password",
                                   password_confirmation: "different" }
    assert_redirected_to edit_password_path

    patch password_path, params: { current_password: "password-for-tests",
                                   password: "short", password_confirmation: "short" }
    assert_redirected_to edit_password_path
    assert AdminUser.authenticate_by(email_address: "me@pea.co.th", password: "password-for-tests")
  end

  test "changing password revokes other sessions" do
    other = Session.create!(admin_user: @admin, ip_address: "10.0.0.9", user_agent: "other-device")
    patch password_path, params: { current_password: "password-for-tests",
                                   password: "a-brand-new-password",
                                   password_confirmation: "a-brand-new-password" }
    refute Session.exists?(other.id)
    get root_path
    assert_response :success   # current session survives
  end
end
```

- [x] **Step 2: implement**

`config/routes.rb` — add: `resource :password, only: %i[edit update]`

`app/controllers/passwords_controller.rb`:
```ruby
class PasswordsController < ApplicationController
  def edit
  end

  def update
    admin = current_admin
    unless admin.authenticate(params[:current_password].to_s)
      return redirect_to edit_password_path, alert: "รหัสผ่านปัจจุบันไม่ถูกต้อง"
    end
    if params[:password].to_s != params[:password_confirmation].to_s
      return redirect_to edit_password_path, alert: "รหัสผ่านใหม่กับการยืนยันไม่ตรงกัน"
    end

    if admin.update(password: params[:password])
      # Revoke every other session — a changed password invalidates old devices.
      admin.sessions.where.not(id: Current.session.id).destroy_all
      Persistence::ArAuditRecorder.new.record(action: "auth.password_changed", actor: admin,
                                              ip: request.remote_ip, user_agent: request.user_agent)
      redirect_to root_path, notice: "เปลี่ยนรหัสผ่านแล้ว"
    else
      redirect_to edit_password_path, alert: admin.errors.full_messages.to_sentence
    end
  end
end
```

`app/views/passwords/edit.html.erb`:
```erb
<h1 class="text-2xl font-bold text-ink">เปลี่ยนรหัสผ่าน</h1>

<%= form_with url: password_path, method: :patch, class: "mt-6 max-w-md space-y-5" do |f| %>
  <div>
    <%= f.label :current_password, "รหัสผ่านปัจจุบัน", class: "mb-1 block font-medium text-ink" %>
    <%= f.password_field :current_password, required: true, autocomplete: "current-password",
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :password, "รหัสผ่านใหม่ (อย่างน้อย 12 ตัวอักษร)", class: "mb-1 block font-medium text-ink" %>
    <%= f.password_field :password, required: true, minlength: 12, autocomplete: "new-password",
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <div>
    <%= f.label :password_confirmation, "ยืนยันรหัสผ่านใหม่", class: "mb-1 block font-medium text-ink" %>
    <%= f.password_field :password_confirmation, required: true, minlength: 12, autocomplete: "new-password",
          class: "w-full rounded-lg border border-gray-300 px-4 py-2.5" %>
  </div>
  <%= f.submit "เปลี่ยนรหัสผ่าน", class: "rounded-lg bg-primary px-4 py-2 font-semibold text-white hover:bg-primary-dark cursor-pointer" %>
<% end %>
```

`app/views/shared/_sidebar.html.erb` — in the footer block, above the logout button, add:
```erb
    <%= link_to "เปลี่ยนรหัสผ่าน", edit_password_path, class: "mt-1 block text-sm text-primary" %>
```

- [x] **Step 3: run** 4 runs PASS; full suite green.
- [x] **Step 4: commit** — `feat: self-service password change revoking other sessions`

---

### Task 10: Sidebar master-data group + audit filter + Capybara system tests

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`, `app/views/audit_logs/index.html.erb`, `test/controllers/home_controller_test.rb`, `test/application_system_test_case.rb`, `README.md`
- Create: `test/system/admin_flows_test.rb`

- [x] **Step 1: sidebar** — inside `<nav>` after the ผู้ใช้งาน link add (view_operations-gated alongside the others):

```erb
      <%= link_to "ค่า EF", emission_factors_path, class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
      <%= link_to "ระดับราคา", pricing_tiers_path, class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
      <%= link_to "หมวดหมู่/หน่วย", categories_path, class: "block rounded-lg px-3 py-2 font-medium hover:bg-surface" %>
```

Update `test/controllers/home_controller_test.rb` "all roles see events and app-users links" test to also assert `/emission_factors`, `/pricing_tiers`, `/categories` links.

- [x] **Step 2: audit filter** — in `app/views/audit_logs/index.html.erb` add `["ข้อมูลหลัก", "master_data."]` to the ประเภท options.

- [x] **Step 3: system tests** — `test/application_system_test_case.rb` (replace driven_by):

```ruby
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # rack_test: fast, no browser dependency. The app is server-rendered —
  # no JS-dependent flows yet. Swap to :selenium when they appear.
  driven_by :rack_test
end
```

`test/system/admin_flows_test.rb`:
```ruby
require "application_system_test_case"

class AdminFlowsTest < ApplicationSystemTestCase
  def login(email, password)
    visit new_session_path
    fill_in "email_address", with: email
    fill_in "password", with: password
    click_on "เข้าสู่ระบบ"
  end

  test "superadmin logs in, sees dashboard, changes an event status" do
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    event = create_core_event!(name_thai: "งานระบบ", status: "collecting")

    login("sa@pea.co.th", "password-for-tests")
    assert_text "ภาพรวมระบบ"

    visit event_path(event.id)
    assert_text "งานระบบ"
    select "in_progress", from: "to"
    click_on "เปลี่ยนสถานะ"
    assert_text "เปลี่ยนสถานะแล้ว"
    assert_equal "in_progress", event.reload.event_status
  end

  test "viewer sees no management controls" do
    AdminUser.create!(email_address: "v@pea.co.th", password: "password-for-tests",
                      name: "วิว", role: :viewer)
    login("v@pea.co.th", "password-for-tests")
    assert_text "ภาพรวมระบบ"
    assert_no_text "บัญชีผู้ดูแล"
    assert_no_text "บันทึกการใช้งาน"
  end

  test "admin edits an emission factor end-to-end" do
    AdminUser.create!(email_address: "ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :admin)
    factor = create_core_emission_factor!(identifier: "ef_system_test", value: 1.0)

    login("ad@pea.co.th", "password-for-tests")
    visit emission_factors_path
    assert_text "ef_system_test"
    visit edit_emission_factor_path(factor.id)
    fill_in "emission_factor[value_per_unit]", with: "4.25"
    click_on "บันทึก"
    assert_text "บันทึกการแก้ไขแล้ว"
    assert_equal 4.25, factor.reload.value_per_unit.to_f
  end

  test "wrong login shows Thai error" do
    login("nobody@pea.co.th", "wrong-password!")
    assert_text "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
  end
end
```

Run with `bin/rails test:system` (system tests don't run under plain `bin/rails test`).

- [x] **Step 4: README** — under Tests add: ``- System tests: `bin/rails test:system` (rack_test driver — no browser needed)``. Update the plans section: Plan 3 done; Plan 4 (deployment + hardening) is next.

- [x] **Step 5: full verification**

```bash
bin/rails test            # ~125+ runs, 0 failures
bin/rails test:system     # 4 runs, 0 failures
for f in test/domain/**/*_test.rb; do ruby -Itest "$f"; done
bin/rubocop               # 0 offenses (run -a first if needed)
bundle exec brakeman -q   # exit 0 (add justified ignores if new mass-assignment warnings appear)
```

- [x] **Step 6: commit** — `feat: master-data navigation, audit filter and system test suite`

---

## Roadmap after this plan

**Plan 4/4 (deployment & hardening):** Rails Dockerfile + GitLab CI mirroring the team pipeline; dedicated DB role (full on `admin`, table grants on `public`) + `REVOKE UPDATE/DELETE` on `admin.audit_logs`; shared cache store for the login rate limiter; session-cleanup task (expired rows); re-enable parallel test workers when pg gem fixes the Ruby 4.0 fork segfault; tier create/delete if operationally needed.
