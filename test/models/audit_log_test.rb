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
end
