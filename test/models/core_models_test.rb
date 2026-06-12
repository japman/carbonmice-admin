require "test_helper"

class CoreModelsTest < ActiveSupport::TestCase
  test "Core::Event maps public.events and scopes out soft-deleted rows" do
    kept = create_core_event!(name_thai: "ยังอยู่")
    gone = create_core_event!(name_thai: "ถูกลบ")
    ActiveRecord::Base.connection.execute(
      "UPDATE public.events SET deleted_at = now() WHERE id = '#{gone.id}'"
    )
    names = Core::Event.kept.pluck(:name_thai)
    assert_includes names, "ยังอยู่"
    refute_includes names, "ถูกลบ"
  end

  test "Core::User maps public.users" do
    create_core_user!(email: "map@example.com", role: "admin", quota: 3)
    u = Core::User.kept.find_by(email: "map@example.com")
    assert_equal "admin", u.role
    assert_equal 3, u.event_quota
  end

  test "Core::CarbonEmission joins category and unit" do
    event = create_core_event!
    create_core_emission!(event_id: event.id, category_thai: "การเดินทาง", pre: 12.5)
    e = Core::CarbonEmission.where(event_id: event.id).includes(:carbon_category, :unit).first
    assert_equal "การเดินทาง", e.carbon_category.name_thai
    assert_equal "kg", e.unit.code
    assert_equal 12.5, e.pre_event_emission.to_f
  end
end
