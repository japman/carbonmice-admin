require "test_helper"

class CoreMasterDataTest < ActiveSupport::TestCase
  test "Core::EmissionFactor maps factors with category" do
    f = create_core_emission_factor!(identifier: "ef_test_factor", name: "ค่าทดสอบ", value: 2.5)
    found = Core::EmissionFactor.kept.find_by(identifier: "ef_test_factor")
    assert_equal 2.5, found.value_per_unit.to_f
    assert_equal "ค่าทดสอบ", found.name
    assert found.carbon_category.name_thai.present?
  end

  test "Core::EventPricingTier and Core::CarbonOffsetPricingTier map their tables" do
    t = create_core_event_pricing_tier!(min: 1, max: 100, price: 5.0)
    assert_equal 5.0, Core::EventPricingTier.kept.find(t.id).price_per_person.to_f

    src = create_core_offset_source!(name: "TGO Test", name_th: "ทีจีโอทดสอบ")
    o = create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.5)
    found = Core::CarbonOffsetPricingTier.kept.find(o.id)
    assert_equal 99.5, found.price_per_emission.to_f
    assert_equal "ทีจีโอทดสอบ", found.carbon_offset_source.name_th
  end
end
