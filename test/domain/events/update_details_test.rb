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

  def test_rejects_province_as_no_longer_editable
    result = Events::UpdateDetails.call(actor: @superadmin, id: "e1",
                                        attrs: { province: "เชียงใหม่" }, repo: @repo, audit: @audit)
    assert result.failure?
    assert_match "ฟิลด์ไม่ได้รับอนุญาต", result.error
    assert_equal "กรุงเทพมหานคร", @repo.find("e1").province   # unchanged
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
