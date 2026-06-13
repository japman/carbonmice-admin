require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "older_than selects only sessions stale past the cutoff" do
    admin = AdminUser.create!(email_address: "s@pea.co.th", password: "password-for-tests",
                              name: "ส", role: :admin)
    old = Session.create!(admin_user: admin, ip_address: "1.1.1.1", user_agent: "x")
    old.update_columns(updated_at: 40.days.ago)
    fresh = Session.create!(admin_user: admin, ip_address: "2.2.2.2", user_agent: "y")
    stale = Session.older_than(30.days)
    assert_includes stale, old
    refute_includes stale, fresh
  end
end
