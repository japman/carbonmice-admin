require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "superadmin sees entries newest first" do
    login(@superadmin)   # writes auth.login_succeeded
    get audit_logs_path
    assert_response :success
    assert_select "td", text: "auth.login_succeeded"
  end

  test "filters by action prefix" do
    login(@superadmin)
    AuditLog.create!(action: "admin_users.created", actor: @superadmin, actor_email: @superadmin.email_address)
    get audit_logs_path, params: { action_prefix: "admin_users." }
    assert_select "td", text: "admin_users.created"
    assert_select "td", text: "auth.login_succeeded", count: 0
  end

  test "admin and viewer are denied" do
    %i[admin viewer].each do |role|
      user = AdminUser.create!(email_address: "#{role}@pea.co.th",
                               password: "password-for-tests", name: role.to_s, role: role)
      login(user)
      get audit_logs_path
      assert_redirected_to root_path
      delete session_path
    end
  end
end
