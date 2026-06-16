require_relative "../../domain_helper"

FakeEvent = Struct.new(:id, :name_thai, :event_status, :updated_by, keyword_init: true)

class FakeEventRepo
  attr_reader :rows

  def initialize(rows = {}, statuses: %w[draft collecting in_progress done complete reject])
    @rows = rows
    @statuses = statuses
  end

  def find(id) = @rows.fetch(id) { raise Ports::NotFound }
  def known_status?(code) = @statuses.include?(code.to_s)

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

  def test_changes_to_any_catalog_status_and_audits
    repo = repo_with("draft")
    # draft -> done was forbidden by the old transition table; now any catalog
    # status is allowed (admin override).
    result = Events::ChangeStatus.call(actor: @superadmin, id: "e1", to: "done",
                                       repo: repo, audit: @audit)
    assert result.success?
    assert_equal "done", repo.find("e1").event_status
    assert_equal "carbonmice-admin:sa@pea.co.th", repo.find("e1").updated_by
    entry = @audit.entries.last
    assert_equal "events.status_changed", entry[:action]
    assert_equal({ "event_status" => { "from" => "draft", "to" => "done" } }, entry[:changes])
  end

  def test_unknown_target_status_is_rejected
    repo = repo_with("draft")
    result = Events::ChangeStatus.call(actor: @superadmin, id: "e1", to: "ascended",
                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_equal "draft", repo.find("e1").event_status
    assert_empty @audit.entries
  end

  def test_viewer_is_denied
    repo = repo_with("collecting")
    result = Events::ChangeStatus.call(actor: @viewer, id: "e1", to: "in_progress",
                                       repo: repo, audit: @audit)
    assert result.failure?
    assert_equal "collecting", repo.find("e1").event_status
    assert_empty @audit.entries
  end

  def test_unknown_event_fails_gracefully
    result = Events::ChangeStatus.call(actor: @superadmin, id: "nope", to: "in_progress",
                                       repo: FakeEventRepo.new, audit: @audit)
    assert result.failure?
    assert_equal "ไม่พบอีเว้นท์", result.error
  end
end
