require "test_helper"
require "rake"

class PurgeSessionsTest < ActiveSupport::TestCase
  setup do
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake.application.rake_require("tasks/sessions", [ Rails.root.join("lib").to_s ])
    Rake::Task.define_task(:environment)
  end

  test "admin:purge_sessions deletes stale rows only" do
    admin = AdminUser.create!(email_address: "p@pea.co.th", password: "password-for-tests",
                              name: "พี", role: :admin)
    old = Session.create!(admin_user: admin, ip_address: "1.1.1.1", user_agent: "x")
    old.update_columns(updated_at: 40.days.ago)
    keep = Session.create!(admin_user: admin, ip_address: "2.2.2.2", user_agent: "y")
    @rake["admin:purge_sessions"].invoke
    refute Session.exists?(old.id)
    assert Session.exists?(keep.id)
  end
end
