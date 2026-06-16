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

  test "add opens a modal and an invalid submit keeps it open with an error" do
    login_admin
    visit emission_factors_path
    click_on "เพิ่มค่า EF"
    assert_selector "turbo-frame#modal h2", text: "เพิ่มค่า EF"
    fill_in "emission_factor[name]", with: "x"
    click_on "สร้าง"
    assert_selector "turbo-frame#modal", text: "เพิ่มค่า EF" # still open
  end

  test "edit opens a modal prefilled with the factor" do
    create_core_emission_factor!(identifier: "ef_editme", value: 3.0)
    login_admin
    visit emission_factors_path
    within "#ef_list" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal", text: "ef_editme"
  end

  test "creating a factor shows the new row and a toast, and closes the modal" do
    create_core_category!(name_thai: "หมวดทดสอบ", name_eng: "test_cat")
    login_admin
    visit emission_factors_path
    click_on "เพิ่มค่า EF"
    fill_in "emission_factor[identifier]", with: "ef_created"
    fill_in "emission_factor[name]", with: "ชื่อใหม่"
    fill_in "emission_factor[source]", with: "src"
    fill_in "emission_factor[value_per_unit]", with: "2.5"
    fill_in "emission_factor[unit_title]", with: "kgCO2e/kg"
    click_on "สร้าง"
    assert_selector "#toast_container", text: "สร้างค่า EF แล้ว"
    assert_selector "#ef_rows", text: "ef_created"
    assert_no_selector "turbo-frame#modal div"
  end

  test "deleting a factor removes its row after the styled confirm" do
    create_core_emission_factor!(identifier: "ef_kill", value: 1.0)
    login_admin
    visit emission_factors_path
    within "#ef_list" do
      click_on "ลบ"
    end
    click_on "ยืนยัน"
    assert_no_selector "#ef_rows", text: "ef_kill"
    assert_selector "#toast_container", text: "ลบค่า EF แล้ว"
  end
end
