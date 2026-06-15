require_relative "../../domain_helper"

FakeOffsetSource = Struct.new(:id, :name, :name_th, :updated_by, :deleted, keyword_init: true)

class FakeOffsetSourceRepo
  attr_reader :rows, :name_taken_flag, :in_use_flag
  attr_accessor :soft_deleted_id

  def initialize(rows: {}, name_taken: false, in_use: false)
    @rows = rows
    @name_taken_flag = name_taken
    @in_use_flag = in_use
    @soft_deleted_id = nil
    @next_id = 1
  end

  def find(id)
    @rows.fetch(id.to_s) { raise Ports::NotFound }
  end

  def list = @rows.values

  def name_taken?(name)
    @name_taken_flag || @rows.values.any? { |r| r.name == name && !r.deleted }
  end

  def create(attrs, created_by:)
    id = (@next_id += 1).to_s
    row = FakeOffsetSource.new(id: id, name: attrs[:name], name_th: attrs[:name_th],
                               updated_by: nil, deleted: false)
    @rows[id] = row
    row
  end

  def update_name_th(id, name_th, updated_by:)
    row = find(id)
    row.name_th = name_th
    row.updated_by = updated_by
    row
  end

  def in_use?(id)
    @in_use_flag
  end

  def soft_delete(id, updated_by:)
    row = find(id)
    row.deleted = true
    row.updated_by = updated_by
    @soft_deleted_id = id
    row
  end
end

class CarbonOffsetSourceDomainTest < Minitest::Test
  def setup
    @audit_entries = []
    entries = @audit_entries
    @audit = Object.new
    @audit.define_singleton_method(:record) { |**entry| entries << entry }
    @admin  = Struct.new(:id, :role, :email_address).new(1, "admin", "ad@pea.co.th")
    @viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
    @repo = FakeOffsetSourceRepo.new
  end

  # --- Create ---

  def test_create_validates_name_present
    result = MasterData::CreateCarbonOffsetSource.call(actor: @admin, attrs: { name: "  ", name_th: "x" },
                                                       repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_create_rejects_duplicate_name
    repo = FakeOffsetSourceRepo.new(name_taken: true)
    result = MasterData::CreateCarbonOffsetSource.call(actor: @admin, attrs: { name: "Biomass", name_th: nil },
                                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_equal "มีแหล่งชื่อนี้อยู่แล้ว", result.error
    assert_empty @audit_entries
  end

  def test_create_success_audits_offset_source_created
    result = MasterData::CreateCarbonOffsetSource.call(actor: @admin,
                                                       attrs: { name: "Solar Energy", name_th: "พลังงานแสงอาทิตย์" },
                                                       repo: @repo, audit: @audit)
    assert result.success?
    assert_equal "Solar Energy", result.value.name
    assert_equal "พลังงานแสงอาทิตย์", result.value.name_th
    assert_equal "master_data.offset_source_created", @audit_entries.last[:action]
    assert_equal @admin, @audit_entries.last[:actor]
    assert_equal({ "name" => "Solar Energy" }, @audit_entries.last[:changes])
  end

  def test_create_strips_name
    result = MasterData::CreateCarbonOffsetSource.call(actor: @admin,
                                                       attrs: { name: "  Wind Energy  ", name_th: nil },
                                                       repo: @repo, audit: @audit)
    assert result.success?
    assert_equal "Wind Energy", result.value.name
  end

  def test_create_blank_name_th_stored_as_nil
    result = MasterData::CreateCarbonOffsetSource.call(actor: @admin,
                                                       attrs: { name: "Hydro", name_th: "   " },
                                                       repo: @repo, audit: @audit)
    assert result.success?
    assert_nil result.value.name_th
  end

  # --- Rename (name_th only) ---

  def test_rename_updates_name_th_with_audit_diff
    repo = FakeOffsetSourceRepo.new(
      rows: { "s1" => FakeOffsetSource.new(id: "s1", name: "Biomass", name_th: "ชีวมวล", updated_by: nil, deleted: false) }
    )
    result = MasterData::RenameCarbonOffsetSource.call(actor: @admin, id: "s1",
                                                       name_th: "ชีวมวลและก๊าซชีวภาพ",
                                                       repo: repo, audit: @audit)
    assert result.success?
    assert_equal "ชีวมวลและก๊าซชีวภาพ", repo.find("s1").name_th
    assert_equal "master_data.offset_source_renamed", @audit_entries.last[:action]
    assert_equal({ "name_th" => { "from" => "ชีวมวล", "to" => "ชีวมวลและก๊าซชีวภาพ" } },
                 @audit_entries.last[:changes])
  end

  def test_rename_clears_name_th_to_nil
    repo = FakeOffsetSourceRepo.new(
      rows: { "s1" => FakeOffsetSource.new(id: "s1", name: "Biomass", name_th: "ชีวมวล", updated_by: nil, deleted: false) }
    )
    result = MasterData::RenameCarbonOffsetSource.call(actor: @admin, id: "s1",
                                                       name_th: "   ",
                                                       repo: repo, audit: @audit)
    assert result.success?
    assert_nil repo.find("s1").name_th
    assert_equal({ "name_th" => { "from" => "ชีวมวล", "to" => nil } },
                 @audit_entries.last[:changes])
  end

  # --- Delete ---

  def test_delete_blocked_when_in_use
    repo = FakeOffsetSourceRepo.new(
      rows: { "s1" => FakeOffsetSource.new(id: "s1", name: "Biomass", name_th: nil, updated_by: nil, deleted: false) },
      in_use: true
    )
    result = MasterData::DeleteCarbonOffsetSource.call(actor: @admin, id: "s1",
                                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_equal "ลบไม่ได้: มีระดับราคา offset ที่อ้างอิงแหล่งนี้อยู่", result.error
    assert_nil repo.soft_deleted_id
    assert_empty @audit_entries
  end

  def test_delete_soft_deletes_with_audit
    repo = FakeOffsetSourceRepo.new(
      rows: { "s1" => FakeOffsetSource.new(id: "s1", name: "Biomass", name_th: nil, updated_by: nil, deleted: false) }
    )
    result = MasterData::DeleteCarbonOffsetSource.call(actor: @admin, id: "s1",
                                                       repo: repo, audit: @audit)
    assert result.success?
    assert repo.find("s1").deleted
    assert_equal "master_data.offset_source_deleted", @audit_entries.last[:action]
    assert_equal({ "name" => "Biomass" }, @audit_entries.last[:changes])
  end

  # --- Viewer denied everywhere ---

  def test_viewer_denied_on_create
    result = MasterData::CreateCarbonOffsetSource.call(actor: @viewer,
                                                       attrs: { name: "Solar", name_th: nil },
                                                       repo: @repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_viewer_denied_on_rename
    repo = FakeOffsetSourceRepo.new(
      rows: { "s1" => FakeOffsetSource.new(id: "s1", name: "B", name_th: nil, updated_by: nil, deleted: false) }
    )
    result = MasterData::RenameCarbonOffsetSource.call(actor: @viewer, id: "s1",
                                                       name_th: "ใหม่",
                                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end

  def test_viewer_denied_on_delete
    repo = FakeOffsetSourceRepo.new(
      rows: { "s1" => FakeOffsetSource.new(id: "s1", name: "B", name_th: nil, updated_by: nil, deleted: false) }
    )
    result = MasterData::DeleteCarbonOffsetSource.call(actor: @viewer, id: "s1",
                                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_empty @audit_entries
  end
end
