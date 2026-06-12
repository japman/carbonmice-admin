require "test_helper"

class ArPricingTierRepositoriesTest < ActiveSupport::TestCase
  test "event tier update stamps and lists ordered" do
    repo = Persistence::ArEventPricingTierRepository.new
    t1 = create_core_event_pricing_tier!(min: 1, max: 100, price: 5.0)
    create_core_event_pricing_tier!(min: 101, max: 200, price: 4.0)
    repo.update(t1.id, { price_per_person: 6.0 }, updated_by: "carbonmice-admin:sa@pea.co.th")
    assert_equal 6.0, t1.reload.price_per_person.to_f
    assert_equal "carbonmice-admin:sa@pea.co.th", t1.reload.updated_by
    assert_equal [ 1, 101 ], repo.list.map(&:min_participants)
  end

  test "offset tier list scopes by source" do
    repo = Persistence::ArOffsetPricingTierRepository.new
    s1 = create_core_offset_source!(name: "S1")
    s2 = create_core_offset_source!(name: "S2")
    create_core_offset_tier!(source_id: s1.id, min: 0, max: 100, price: 99.0)
    create_core_offset_tier!(source_id: s2.id, min: 0, max: 100, price: 88.0)
    assert_equal 1, repo.list(source_id: s1.id).size
    assert_equal 2, repo.list.size
  end
end
