require "application_system_test_case"

class HotwireInfraTest < ApplicationSystemTestCase
  test "authenticated layout includes the modal frame and toast container" do
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
    assert_selector "turbo-frame#modal", visible: :all
    assert_selector "#toast_container", visible: :all
  end

  test "a redirect carrying a flash alert renders it as a toast" do
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
    # opening an unknown event id redirects to the list with a flash alert,
    # which the layout renders into the toast container.
    visit event_path("not-a-uuid")
    assert_selector "#toast_container [data-controller='toast']", text: "ไม่พบอีเว้นท์"
  end
end
