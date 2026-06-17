require "application_system_test_case"

class AppUsersTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_admin
    AdminUser.create!(email_address: "au_ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "au_ad@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "live filter re-renders au_list and advances URL" do
    create_core_user!(email: "filter_alice@example.com", display_name: "อลิซ")
    create_core_user!(email: "filter_bob@example.com", display_name: "บ็อบ")
    login_admin
    visit app_users_path
    assert_selector "#au_list", text: "filter_alice@example.com"
    assert_selector "#au_list", text: "filter_bob@example.com"

    within "form[data-controller='filter']" do
      fill_in "search", with: "อลิซ"
    end
    # Wait for turbo frame to re-render
    assert_selector "#au_list", text: "filter_alice@example.com"
    assert_no_selector "#au_list", text: "filter_bob@example.com"
    assert_current_path(/search=/)
  end

  test "editing role/quota via modal updates the row and shows a toast" do
    user = create_core_user!(email: "edit_au@example.com", role: "user", quota: 1)
    login_admin
    visit app_users_path
    assert_selector "##{dom_id(user)}", text: "user"
    within "##{dom_id(user)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ไขผู้ใช้งาน: edit_au@example.com"
    within "turbo-frame#modal" do
      select "admin", from: "app_user[role]"
      fill_in "app_user[event_quota]", with: "99"
      click_on "บันทึก"
    end
    assert_selector "#toast_container", text: "บันทึกการแก้ไขแล้ว"
    assert_selector "##{dom_id(user)}", text: "admin"
    assert_selector "##{dom_id(user)}", text: "99"
    assert_no_selector "turbo-frame#modal div"
  end

  test "lists the total carbon credit summed across offset sources" do
    user = create_core_user!(email: "credits_au@example.com", display_name: "เครดิตรวม")
    s1 = create_core_offset_source!(name: "Solar")
    s2 = create_core_offset_source!(name: "Wind")
    create_core_carbon_credit!(user_id: user.id, amount: 100, source_id: s1.id)
    create_core_carbon_credit!(user_id: user.id, amount: 50, source_id: s2.id)
    login_admin
    visit app_users_path
    # 5th column is the summed credit total (after name, email, role, quota).
    assert_selector "##{dom_id(user)} td:nth-child(5)", text: "150"
  end

  test "shows a dash when a user has no carbon credits" do
    user = create_core_user!(email: "nocredit_au@example.com", display_name: "ไม่มีเครดิต")
    login_admin
    visit app_users_path
    assert_selector "##{dom_id(user)} td:nth-child(5)", text: "—"
  end

  test "server-rejected submit (invalid role) keeps modal open with error" do
    user = create_core_user!(email: "reject_au@example.com", role: "user", quota: 0)
    login_admin
    visit app_users_path
    within "##{dom_id(user)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2"
    # Inject an invalid role option via JS to bypass HTML select constraints,
    # then select it so Chrome actually submits it.
    page.execute_script(<<~JS)
      var sel = document.querySelector("select[name='app_user[role]']");
      var opt = document.createElement('option');
      opt.value = 'totally_invalid_role';
      opt.text = 'Invalid';
      sel.appendChild(opt);
      sel.value = 'totally_invalid_role';
    JS
    within "turbo-frame#modal" do
      click_on "บันทึก"
    end
    assert_selector "turbo-frame#modal .text-danger"
  end
end
