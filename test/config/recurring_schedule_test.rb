require "test_helper"
require "fugit"

class RecurringScheduleTest < ActiveSupport::TestCase
  test "production recurring schedule defines purge_sessions for PurgeSessionsJob" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    task = config.fetch("production").fetch("purge_sessions")

    assert_equal "PurgeSessionsJob", task["class"]
    assert task["schedule"].present?, "purge_sessions must define a non-empty schedule"
    assert Fugit.parse(task["schedule"]), "purge_sessions schedule must be Fugit-parseable: #{task["schedule"]}"
  end

  test "every production recurring task has a Fugit-parseable schedule" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"))
    config.fetch("production").each do |key, task|
      assert Fugit.parse(task["schedule"]), "#{key} schedule must be Fugit-parseable: #{task["schedule"]}"
    end
  end
end
