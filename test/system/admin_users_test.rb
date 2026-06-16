require "application_system_test_case"

class AdminUsersTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_superadmin
    @superadmin ||= AdminUser.create!(email_address: "adm_sa@pea.co.th", password: "password-for-tests",
                                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "adm_sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "live filter by name re-renders adm_list and advances URL" do
    @superadmin = AdminUser.create!(email_address: "adm_sa@pea.co.th", password: "password-for-tests",
                                    name: "ซุป", role: :superadmin)
    AdminUser.create!(email_address: "visible@pea.co.th", password: "password-for-tests",
                      name: "มองเห็น", role: :admin)
    AdminUser.create!(email_address: "hidden@pea.co.th", password: "password-for-tests",
                      name: "ซ่อนอยู่", role: :admin)
    login_superadmin
    visit admin_users_path
    assert_selector "#adm_list", text: "visible@pea.co.th"
    assert_selector "#adm_list", text: "hidden@pea.co.th"

    within "form[data-controller='filter']" do
      fill_in "search", with: "มองเห็น"
    end
    assert_selector "#adm_list", text: "visible@pea.co.th"
    assert_no_selector "#adm_list", text: "hidden@pea.co.th"
    assert_current_path(/search=/)
  end

  test "creating an admin via modal prepends the row and shows a toast" do
    login_superadmin
    visit admin_users_path
    click_on "เพิ่มผู้ดูแล"
    assert_selector "turbo-frame#modal h2", text: "เพิ่มผู้ดูแล"
    within "turbo-frame#modal" do
      fill_in "admin_user[name]", with: "ใหม่ระบบ"
      fill_in "admin_user[email_address]", with: "newsys@pea.co.th"
      fill_in "admin_user[password]", with: "password-for-tests"
      select "Admin", from: "admin_user[role]"
      click_on "สร้างบัญชี"
    end
    assert_selector "#toast_container", text: "สร้างบัญชีผู้ดูแลแล้ว"
    assert_selector "#adm_rows", text: "newsys@pea.co.th"
    assert_no_selector "turbo-frame#modal div"
  end

  test "editing role/active via modal updates the row and shows a toast" do
    @superadmin = AdminUser.create!(email_address: "adm_sa@pea.co.th", password: "password-for-tests",
                                    name: "ซุป", role: :superadmin)
    target = AdminUser.create!(email_address: "edit_sys@pea.co.th", password: "password-for-tests",
                               name: "แก้ไข", role: :admin)
    login_superadmin
    visit admin_users_path
    within "##{dom_id(target)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ไขผู้ดูแล: แก้ไข"
    within "turbo-frame#modal" do
      select "Viewer", from: "admin_user[role]"
      click_on "บันทึก"
    end
    assert_selector "#toast_container", text: "บันทึกการแก้ไขแล้ว"
    assert_selector "##{dom_id(target)}", text: "ผู้ชม"
    assert_no_selector "turbo-frame#modal div"
  end

  test "server-rejected create (duplicate email) keeps modal open with error" do
    login_superadmin
    # adm_sa@pea.co.th already exists
    visit admin_users_path
    click_on "เพิ่มผู้ดูแล"
    assert_selector "turbo-frame#modal h2", text: "เพิ่มผู้ดูแล"
    within "turbo-frame#modal" do
      fill_in "admin_user[name]", with: "ซ้ำ"
      fill_in "admin_user[email_address]", with: "adm_sa@pea.co.th"
      fill_in "admin_user[password]", with: "password-for-tests"
      click_on "สร้างบัญชี"
    end
    assert_selector "turbo-frame#modal .text-danger"
  end
end
