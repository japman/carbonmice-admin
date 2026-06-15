require_relative "../../domain_helper"

FakeCredit = Struct.new(:id, :user_id, :carbon_credit, :carbon_offset_source_id,
                        :deleted, :updated_by, :created_by,
                        keyword_init: true)

class FakeCreditRepo
  attr_reader :rows
  def initialize(rows = {}) = @rows = rows
  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def list(user_id: nil, page: 1) = @rows.values.reject(&:deleted)
  def create(attrs, created_by:)
    row = FakeCredit.new(id: (@rows.size + 1).to_s, deleted: false, created_by: created_by, **attrs)
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

class CarbonCreditDomainTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @admin  = Struct.new(:id, :role, :email_address).new(1, "admin",  "ad@pea.co.th")
    @viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    @repo = FakeCreditRepo.new
  end

  def valid_attrs
    { user_id: "user-uuid-1", carbon_credit: "100", carbon_offset_source_id: "" }
  end

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  def test_create_requires_user_id
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(user_id: "  "), repo: @repo, audit: @audit)
    assert result.failure?
    assert_match "กรุณาเลือกผู้ใช้", result.error
    assert_empty @audit_entries
  end

  def test_create_rejects_zero_amount
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "0"), repo: @repo, audit: @audit)
    assert result.failure?
    assert_match "จำนวน carbon credit", result.error
    assert_empty @audit_entries
  end

  def test_create_rejects_negative_amount
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "-5"), repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_create_rejects_non_integer_amount
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "1.5"), repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_create_success_audits_carbon_credit_created
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "50"), repo: @repo, audit: @audit)
    assert result.success?
    assert_equal 50, result.value.carbon_credit
    assert_nil result.value.carbon_offset_source_id   # blank string → nil
    assert_equal "carbonmice-admin:ad@pea.co.th", result.value.created_by
    assert_equal "master_data.carbon_credit_created", @audit_entries.last[:action]
    assert_equal({ "user_id" => "user-uuid-1", "carbon_credit" => 50 }, @audit_entries.last[:changes])
  end

  def test_create_stores_source_id_when_provided
    result = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "10", carbon_offset_source_id: "src-1"),
               repo: @repo, audit: @audit)
    assert result.success?
    assert_equal "src-1", result.value.carbon_offset_source_id
  end

  # ---------------------------------------------------------------------------
  # Update
  # ---------------------------------------------------------------------------

  def test_update_rejects_unknown_key_user_id
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "10"),
                                                  repo: @repo, audit: @audit).value
    result = MasterData::UpdateCarbonCredit.call(actor: @admin, id: created.id,
               attrs: { user_id: "other-user" }, repo: @repo, audit: @audit)
    assert result.failure?
    assert_match "ฟิลด์ไม่ได้รับอนุญาต", result.error
    assert_equal "user-uuid-1", @repo.find(created.id).user_id   # unchanged
  end

  def test_update_edits_amount_with_diff_audit
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "10"),
                                                  repo: @repo, audit: @audit).value
    @audit_entries.clear
    result = MasterData::UpdateCarbonCredit.call(actor: @admin, id: created.id,
               attrs: { carbon_credit: "999" }, repo: @repo, audit: @audit)
    assert result.success?
    assert_equal 999, result.value.carbon_credit
    assert_equal "master_data.carbon_credit_updated", @audit_entries.last[:action]
    assert_equal({ "carbon_credit" => { "from" => 10, "to" => 999 } }, @audit_entries.last[:changes])
  end

  def test_update_edits_source_with_diff_audit
    created = MasterData::CreateCarbonCredit.call(actor: @admin,
               attrs: valid_attrs.merge(carbon_credit: "10", carbon_offset_source_id: "src-1"),
               repo: @repo, audit: @audit).value
    @audit_entries.clear
    result = MasterData::UpdateCarbonCredit.call(actor: @admin, id: created.id,
               attrs: { carbon_offset_source_id: "" }, repo: @repo, audit: @audit)
    assert result.success?
    assert_nil result.value.carbon_offset_source_id   # blank → nil
    assert_equal "master_data.carbon_credit_updated", @audit_entries.last[:action]
  end

  def test_update_rejects_zero_amount
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "10"),
                                                  repo: @repo, audit: @audit).value
    result = MasterData::UpdateCarbonCredit.call(actor: @admin, id: created.id,
               attrs: { carbon_credit: "0" }, repo: @repo, audit: @audit)
    assert result.failure?
  end

  def test_update_fails_if_no_editable_fields
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "10"),
                                                  repo: @repo, audit: @audit).value
    result = MasterData::UpdateCarbonCredit.call(actor: @admin, id: created.id,
               attrs: {}, repo: @repo, audit: @audit)
    assert result.failure?
    assert_match "ไม่มีข้อมูลให้แก้ไข", result.error
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  def test_delete_soft_deletes_with_audit
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "42"),
                                                  repo: @repo, audit: @audit).value
    @audit_entries.clear
    result = MasterData::DeleteCarbonCredit.call(actor: @admin, id: created.id,
               repo: @repo, audit: @audit)
    assert result.success?
    assert @repo.find(created.id).deleted
    assert_equal "master_data.carbon_credit_deleted", @audit_entries.last[:action]
    assert_equal({ "carbon_credit" => 42 }, @audit_entries.last[:changes])
  end

  # ---------------------------------------------------------------------------
  # Viewer denied
  # ---------------------------------------------------------------------------

  def test_viewer_denied_on_create
    result = MasterData::CreateCarbonCredit.call(actor: @viewer, attrs: valid_attrs.merge(carbon_credit: "10"),
               repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_viewer_denied_on_update
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "10"),
                                                  repo: @repo, audit: @audit).value
    @audit_entries.clear
    result = MasterData::UpdateCarbonCredit.call(actor: @viewer, id: created.id,
               attrs: { carbon_credit: "20" }, repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_viewer_denied_on_delete
    created = MasterData::CreateCarbonCredit.call(actor: @admin, attrs: valid_attrs.merge(carbon_credit: "10"),
                                                  repo: @repo, audit: @audit).value
    @audit_entries.clear
    result = MasterData::DeleteCarbonCredit.call(actor: @viewer, id: created.id,
               repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end
end
