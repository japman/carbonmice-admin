require "test_helper"

class RecurringScheduleTest < ActiveSupport::TestCase
  test "production recurring schedule defines purge_sessions for PurgeSessionsJob" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    task = config.fetch("production").fetch("purge_sessions")

    assert_equal "PurgeSessionsJob", task["class"]
    assert task["schedule"].present?, "purge_sessions must define a non-empty schedule"
  end
end
