require "test_helper"

class PricingTiersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "index shows both tier tables grouped" do
    login(@superadmin)
    create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    src = create_core_offset_source!(name: "TGO-X", name_th: "ทีจีโอเอ็กซ์")
    create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.0)
    get pricing_tiers_path
    assert_response :success
    assert_select "td", text: "5.0"
    assert_match "ทีจีโอเอ็กซ์", response.body
  end

  test "updates an event tier price with audit" do
    login(@superadmin)
    tier = create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    get edit_event_pricing_tier_path(tier.id)
    assert_response :success
    assert_difference -> { AuditLog.where(action: "master_data.event_tier_updated").count } => 1 do
      patch event_pricing_tier_path(tier.id), params: { tier: { price_per_person: "7.25" } }
    end
    assert_equal 7.25, tier.reload.price_per_person.to_f
  end

  test "updates an offset tier with overlap rejection" do
    login(@superadmin)
    src = create_core_offset_source!(name: "S")
    a = create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.0)
    create_core_offset_tier!(source_id: src.id, min: 101, max: 200, price: 89.0)
    patch offset_pricing_tier_path(a.id), params: { tier: { max_emission: "150" } }
    assert_redirected_to edit_offset_pricing_tier_path(a.id)
    assert_equal 100, a.reload.max_emission
  end

  test "viewer reads index but cannot write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    tier = create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    get pricing_tiers_path
    assert_response :success
    patch event_pricing_tier_path(tier.id), params: { tier: { price_per_person: "1" } }
    assert_redirected_to root_path
    assert_equal 5.0, tier.reload.price_per_person.to_f
  end
end
