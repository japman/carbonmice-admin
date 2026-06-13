require "test_helper"

class PurgeSessionsJobTest < ActiveJob::TestCase
  test "perform_now deletes stale sessions only and returns the deleted count" do
    admin = AdminUser.create!(email_address: "j@pea.co.th", password: "password-for-tests",
                              name: "เจ", role: :admin)
    stale = Session.create!(admin_user: admin, ip_address: "1.1.1.1", user_agent: "x")
    stale.update_columns(updated_at: 40.days.ago)
    fresh = Session.create!(admin_user: admin, ip_address: "2.2.2.2", user_agent: "y")

    deleted = PurgeSessionsJob.perform_now

    refute Session.exists?(stale.id)
    assert Session.exists?(fresh.id)
    assert_equal 1, deleted
  end
end
