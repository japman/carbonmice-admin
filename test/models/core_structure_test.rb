require "test_helper"

class CoreStructureTest < ActiveSupport::TestCase
  test "Go-owned public tables exist in the test database" do
    %w[events users event_statuses carbon_emissions carbon_categories units].each do |table|
      assert ActiveRecord::Base.connection.data_source_exists?("public.#{table}"),
             "expected public.#{table} to exist (core_structure.sql not loaded?)"
    end
  end

  test "core factories build a full event chain" do
    event = create_core_event!(name_thai: "งานทดสอบ", status: "draft")
    assert_equal "งานทดสอบ", event.name_thai
    assert_equal "draft", event.event_status

    user = create_core_user!(email: "u@example.com", role: "user", quota: 2)
    assert_equal 2, user.event_quota
  end
end
