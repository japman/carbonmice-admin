require "application_system_test_case"

class AuditLogsTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_superadmin
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                                    name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "choosing an action_prefix re-renders al_list without full reload and advances URL" do
    login_superadmin
    # After login, auth.login_succeeded is already in the log.
    # Create an admin_users entry to filter on.
    AuditLog.create!(action: "admin_users.created", actor: @superadmin,
                     actor_email: @superadmin.email_address)

    visit audit_logs_path

    assert_selector "#al_list", text: "auth.login_succeeded"
    assert_selector "#al_list", text: "admin_users.created"

    within "form[data-controller='filter']" do
      select "บัญชีผู้ดูแล", from: "action_prefix"
    end

    within "#al_list" do
      assert_text "admin_users.created"
      assert_no_text "auth.login_succeeded"
    end
    assert_current_path(/action_prefix=admin_users/)
  end
end
