require "application_system_test_case"

class PricingTiersTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_admin
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "editing an event tier opens modal, saves, updates the row in place with toast" do
    tier = create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    login_admin
    visit pricing_tiers_path

    within "##{dom_id(tier)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ไขระดับราคา (อีเว้นท์)"

    within "turbo-frame#modal" do
      fill_in "tier[price_per_person]", with: "12.5"
      click_on "บันทึก"
    end

    assert_selector "#toast_container", text: "บันทึกระดับราคาแล้ว"
    assert_selector "##{dom_id(tier)}", text: "12.5"
    assert_no_selector "turbo-frame#modal div"
  end

  test "editing an offset tier opens modal, saves, updates the row in place with toast" do
    src = create_core_offset_source!(name: "TGO", name_th: "ทีจีโอ")
    tier = create_core_offset_tier!(source_id: src.id, min: 0, max: 100, price: 99.0)
    login_admin
    visit pricing_tiers_path

    within "##{dom_id(tier)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ไขระดับราคา (ชดเชยคาร์บอน)"

    within "turbo-frame#modal" do
      fill_in "tier[price_per_emission]", with: "75.0"
      click_on "บันทึก"
    end

    assert_selector "#toast_container", text: "บันทึกระดับราคาแล้ว"
    assert_selector "##{dom_id(tier)}", text: "75.0"
    assert_no_selector "turbo-frame#modal div"
  end

  test "invalid event tier edit keeps modal open with text-danger error" do
    tier = create_core_event_pricing_tier!(min: 1, max: 1000, price: 5.0)
    login_admin
    visit pricing_tiers_path

    within "##{dom_id(tier)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ไขระดับราคา (อีเว้นท์)"

    # Set min > max to trigger bounds rejection
    within "turbo-frame#modal" do
      fill_in "tier[min_participants]", with: "900"
      fill_in "tier[max_participants]", with: "10"
      click_on "บันทึก"
    end

    assert_selector "turbo-frame#modal .text-danger"
  end
end
