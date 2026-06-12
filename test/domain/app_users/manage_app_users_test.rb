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
