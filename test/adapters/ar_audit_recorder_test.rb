require "test_helper"

class ArAuditRecorderTest < ActiveSupport::TestCase
  setup do
    @actor = AdminUser.create!(email_address: "sa@pea.co.th",
                               password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  test "records a data-change entry with actor and target" do
    target = AdminUser.create!(email_address: "t@pea.co.th",
                               password: "password-for-tests", name: "เป้า")
    Persistence::ArAuditRecorder.new.record(
      action: "admin_users.updated", actor: @actor, target: target,
      changes: { "role" => { "from" => "viewer", "to" => "admin" } },
      ip: "10.0.0.1", user_agent: "test"
    )
    log = AuditLog.order(:id).last
    assert_equal "admin_users.updated", log.action
    assert_equal @actor.id, log.actor_id
    assert_equal "sa@pea.co.th", log.actor_email
    assert_equal "AdminUser", log.target_type
    assert_equal target.id.to_s, log.target_id
    assert_equal({ "role" => { "from" => "viewer", "to" => "admin" } }, log.change_set)
  end

  test "records an actorless entry (failed login)" do
    Persistence::ArAuditRecorder.new.record(
      action: "auth.login_failed", actor_email: "ghost@pea.co.th", ip: "10.0.0.2", user_agent: "test"
    )
    log = AuditLog.order(:id).last
    assert_nil log.actor_id
    assert_equal "ghost@pea.co.th", log.actor_email
  end

  test "constructor default ip and user_agent are used when record is called without them" do
    target = AdminUser.create!(email_address: "t2@pea.co.th",
                               password: "password-for-tests", name: "เป้า")
    Persistence::ArAuditRecorder.new(ip: "9.9.9.9", user_agent: "ua").record(
      action: "admin_users.updated", actor: @actor, target: target
    )
    log = AuditLog.order(:id).last
    assert_equal "9.9.9.9", log.ip_address
    assert_equal "ua", log.user_agent
  end

  test "explicit ip passed to record overrides constructor default" do
    target = AdminUser.create!(email_address: "t3@pea.co.th",
                               password: "password-for-tests", name: "เป้า")
    Persistence::ArAuditRecorder.new(ip: "9.9.9.9", user_agent: "ua").record(
      action: "admin_users.updated", actor: @actor, target: target, ip: "1.2.3.4"
    )
    log = AuditLog.order(:id).last
    assert_equal "1.2.3.4", log.ip_address
    assert_equal "ua", log.user_agent
  end

  test "explicit user_agent passed to record overrides constructor default" do
    target = AdminUser.create!(email_address: "t4@pea.co.th",
                               password: "password-for-tests", name: "เป้า")
    Persistence::ArAuditRecorder.new(ip: "9.9.9.9", user_agent: "ua").record(
      action: "admin_users.updated", actor: @actor, target: target, user_agent: "override-ua"
    )
    log = AuditLog.order(:id).last
    assert_equal "override-ua", log.user_agent
    assert_equal "9.9.9.9", log.ip_address
  end
end
