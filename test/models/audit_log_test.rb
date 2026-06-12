require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "entries are insert-only" do
    log = AuditLog.create!(action: "auth.login_succeeded", actor_email: "a@pea.co.th")
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.update!(action: "tampered") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.destroy! }
  end

  test "requires an action" do
    refute AuditLog.new.valid?
  end

  test "deleting an actor nullifies actor_id but preserves the entry" do
    actor = AdminUser.create!(email_address: "gone@pea.co.th",
                              password: "password-for-tests", name: "ไป", role: :admin)
    log = AuditLog.create!(action: "auth.login_succeeded", actor: actor, actor_email: actor.email_address)
    actor.destroy!
    log = AuditLog.find(log.id)
    assert_nil log.actor_id
    assert_equal "gone@pea.co.th", log.actor_email
  end
end
