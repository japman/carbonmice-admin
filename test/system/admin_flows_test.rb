require "application_system_test_case"

class AdminFlowsTest < ApplicationSystemTestCase
  def login(email, password)
    visit new_session_path
    fill_in "email_address", with: email
    fill_in "password", with: password
    click_on "เข้าสู่ระบบ"
  end

  test "superadmin logs in, sees dashboard, changes an event status" do
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    event = create_core_event!(name_thai: "งานระบบ", status: "collecting")

    login("sa@pea.co.th", "password-for-tests")
    assert_text "ภาพรวมระบบ"

    visit event_path(event.id)
    assert_text "งานระบบ"
    select "in_progress", from: "to"
    click_on "เปลี่ยนสถานะ"
    assert_text "เปลี่ยนสถานะแล้ว"
    assert_equal "in_progress", event.reload.event_status
  end

  test "viewer sees no management controls" do
    AdminUser.create!(email_address: "v@pea.co.th", password: "password-for-tests",
                      name: "วิว", role: :viewer)
    login("v@pea.co.th", "password-for-tests")
    assert_text "ภาพรวมระบบ"
    assert_no_text "บัญชีผู้ดูแล"
    assert_no_text "บันทึกการใช้งาน"
  end

  test "admin edits an emission factor end-to-end" do
    AdminUser.create!(email_address: "ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :admin)
    factor = create_core_emission_factor!(identifier: "ef_system_test", value: 1.0)

    login("ad@pea.co.th", "password-for-tests")
    visit emission_factors_path
    assert_text "ef_system_test"
    visit edit_emission_factor_path(factor.id)
    fill_in "emission_factor[value_per_unit]", with: "4.25"
    click_on "บันทึก"
    assert_text "บันทึกการแก้ไขแล้ว"
    assert_equal 4.25, factor.reload.value_per_unit.to_f
  end

  test "wrong login shows Thai error" do
    login("nobody@pea.co.th", "wrong-password!")
    assert_text "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
  end
end
