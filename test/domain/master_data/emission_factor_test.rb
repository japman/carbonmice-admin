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
