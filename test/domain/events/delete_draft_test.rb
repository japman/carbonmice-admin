require_relative "../../domain_helper"

FakeDeletableEvent = Struct.new(:id, :name_thai, :name_eng, :event_status, keyword_init: true)

class FakeDeleteRepo
  attr_reader :deleted

  def initialize(rows = {}, fk_locked: false)
    @rows = rows
    @fk_locked = fk_locked
    @deleted = []
  end

  def find(id) = @rows.fetch(id) { raise Ports::NotFound }

  def hard_delete(id)
    row = find(id)
    raise Ports::ValidationFailed, "ลบถาวรไม่ได้: อีเว้นท์นี้มีข้อมูลอื่นอ้างอิงอยู่" if @fk_locked
    @rows.delete(id)
    @deleted << id
    row
  end
end

class FakeDeleteAudit
  attr_reader :entries
  def initialize = @entries = []
  def record(**entry) = @entries << entry
end

class DeleteDraftTest < Minitest::Test
  def setup
    @audit = FakeDeleteAudit.new
    @superadmin = Struct.new(:id, :role, :email_address).new(1, "superadmin", "sa@pea.co.th")
    @viewer = Struct.new(:id, :role, :email_address).new(2, "viewer", "v@pea.co.th")
  end

  def repo_with(status, fk_locked: false)
    FakeDeleteRepo.new(
      { "e1" => FakeDeletableEvent.new(id: "e1", name_thai: "งาน", name_eng: "Ev", event_status: status) },
      fk_locked: fk_locked
    )
  end

  def test_deletes_a_draft_and_audits
    repo = repo_with("draft")
    result = Events::DeleteDraft.call(actor: @superadmin, id: "e1", repo: repo, audit: @audit)
    assert result.success?
    assert_equal [ "e1" ], repo.deleted
    entry = @audit.entries.last
    assert_equal "events.deleted", entry[:action]
    assert_equal "draft", entry[:changes]["event_status"]
    assert_equal "งาน", entry[:changes]["name"]
  end

  def test_rejects_non_draft_event
    repo = repo_with("collecting")
    result = Events::DeleteDraft.call(actor: @superadmin, id: "e1", repo: repo, audit: @audit)
    assert result.failure?
    assert_empty repo.deleted
    assert_empty @audit.entries
  end

  def test_denies_role_without_manage_events
    repo = repo_with("draft")
    result = Events::DeleteDraft.call(actor: @viewer, id: "e1", repo: repo, audit: @audit)
    assert result.failure?
    assert_empty repo.deleted
    assert_empty @audit.entries
  end

  def test_surfaces_fk_block_as_a_failure
    repo = repo_with("draft", fk_locked: true)
    result = Events::DeleteDraft.call(actor: @superadmin, id: "e1", repo: repo, audit: @audit)
    assert result.failure?
    assert_match "อ้างอิง", result.error
    assert_empty @audit.entries
  end

  def test_missing_event_is_a_failure
    repo = FakeDeleteRepo.new({})
    result = Events::DeleteDraft.call(actor: @superadmin, id: "nope", repo: repo, audit: @audit)
    assert result.failure?
  end
end
