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
