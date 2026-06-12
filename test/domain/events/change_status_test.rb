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
      "draft"            => [ "draft", "pending_email_confirm", "" ],
      "email_confirmed"  => [ "survey_published" ],
      "quotation_review" => [ "quotation" ],
      "survey_published" => [ "collecting" ],
      "collecting"       => [ "quotation_review", "reject" ],
      "in_progress"      => [ "collecting" ],
      "done"             => [ "in_progress" ],
      "complete"         => [ "done", "collecting" ],
      "carbon_credit"    => [ "complete" ],
      "offset_carbon"    => [ "complete", "carbon_credit" ],
      "send_data"        => [ "complete", "offset_carbon" ],
      "reject"           => [ "in_progress" ]
    }
    assert_equal expected, Events::ChangeStatus::TRANSITIONS
    refute Events::ChangeStatus::TRANSITIONS.key?("pending_email_confirm")
    refute Events::ChangeStatus::TRANSITIONS.key?("quotation")
  end
end
