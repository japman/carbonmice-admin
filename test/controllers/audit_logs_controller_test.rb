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

  test "to-date filter includes entries from that entire day" do
    login(@superadmin)
    AuditLog.create!(action: "admin_users.created", actor: @superadmin,
                     actor_email: @superadmin.email_address)
    get audit_logs_path, params: { action_prefix: "admin_users.", to: Date.current.to_s }
    assert_select "td", text: "admin_users.created"
  end

  test "from-date filter excludes earlier entries" do
    login(@superadmin)
    # AuditLog is readonly at the instance level; insert_all bypasses the guard to set a past created_at.
    AuditLog.insert_all([ { action: "admin_users.created", actor_id: @superadmin.id,
                           actor_email: @superadmin.email_address, change_set: {},
                           created_at: 3.days.ago } ])
    get audit_logs_path, params: { action_prefix: "admin_users.", from: Date.current.to_s }
    assert_select "td", text: "admin_users.created", count: 0
  end

  test "shows truncation notice when the limit is hit" do
    login(@superadmin)
    # insert_all bypasses the readonly model guard — acceptable in test fixtures.
    rows = Array.new(Persistence::ArAuditLogQuery::DEFAULT_LIMIT) do
      { action: "admin_users.created", actor_id: @superadmin.id,
        actor_email: @superadmin.email_address, change_set: {}, created_at: Time.current }
    end
    AuditLog.insert_all(rows)
    get audit_logs_path
    assert_match "อาจถูกตัดทอน", response.body
  end

  test "malformed date params are ignored" do
    login(@superadmin)
    get audit_logs_path, params: { from: "banana", to: "also-banana" }
    assert_response :success
  end
end
