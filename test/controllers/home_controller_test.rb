require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def login_as(role)
    admin = AdminUser.create!(email_address: "#{role}@pea.co.th",
                              password: "password-for-tests", name: role.to_s, role: role)
    post session_path, params: { email_address: admin.email_address, password: "password-for-tests" }
    admin
  end

  test "superadmin sees admin-management and audit links" do
    login_as(:superadmin)
    get root_path
    assert_select "nav a[href=?]", "/admin_users"
    assert_select "nav a[href=?]", "/audit_logs"
  end

  test "admin sees neither admin-management nor audit links" do
    login_as(:admin)
    get root_path
    assert_select "nav a[href=?]", "/admin_users", count: 0
    assert_select "nav a[href=?]", "/audit_logs", count: 0
  end

  test "all roles see events and app-users links" do
    login_as(:viewer)
    get root_path
    assert_select "nav a[href=?]", "/events"
    assert_select "nav a[href=?]", "/app_users"
    assert_select "nav a[href=?]", "/emission_factors"
    assert_select "nav a[href=?]", "/pricing_tiers"
    assert_select "nav a[href=?]", "/categories"
  end

  test "viewer sees no management links" do
    login_as(:viewer)
    get root_path
    assert_select "nav a[href=?]", "/", count: 1
    assert_select "nav a[href=?]", "/admin_users", count: 0
    assert_select "nav a[href=?]", "/audit_logs", count: 0
  end
end
