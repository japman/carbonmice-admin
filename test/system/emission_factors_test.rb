require "application_system_test_case"

class EmissionFactorsTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_admin
    AdminUser.create!(email_address: "ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :admin)
    visit new_session_path
    fill_in "email_address", with: "ad@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "typing in search live-filters the list without a full page reload" do
    create_core_emission_factor!(identifier: "ef_alpha", value: 1.0)
    create_core_emission_factor!(identifier: "ef_beta", value: 2.0)
    login_admin
    visit emission_factors_path
    assert_selector "#ef_list", text: "ef_alpha"
    assert_selector "#ef_list", text: "ef_beta"

    fill_in "search", with: "alpha"
    within "#ef_list" do
      assert_text "ef_alpha"
      assert_no_text "ef_beta"
    end
    assert_current_path(/search=alpha/)
  end
end
