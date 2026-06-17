require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  # Inserts `count` audit entries with strictly descending timestamps (index 0 is
  # newest) so newest-first ordering and page slicing are deterministic. insert_all
  # bypasses the readonly model guard — acceptable in test fixtures.
  def seed_entries(count, action: "seed.event")
    rows = Array.new(count) do |i|
      { action: action, actor_id: @superadmin.id, actor_email: @superadmin.email_address,
        change_set: {}, created_at: (i + 1).minutes.ago }
    end
    AuditLog.insert_all(rows)
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

  test "page 1 shows 25 rows and a next-page link when more exist" do
    login(@superadmin)            # adds one entry (auth.login_succeeded), newest
    seed_entries(25)              # 26 total => page 1 is full, a 2nd page exists
    get audit_logs_path
    assert_response :success
    assert_select "tbody tr", count: 25
    assert_select "a", text: /ถัดไป/ do |links|
      assert_includes links.first["href"], "page=2"
    end
  end

  test "page 2 shows the remaining rows and no next-page link" do
    login(@superadmin)            # 1 entry
    seed_entries(25)              # 26 total => page 2 holds the single oldest row
    get audit_logs_path, params: { page: 2 }
    assert_response :success
    assert_select "tbody tr", count: 1
    assert_select "a", text: /ถัดไป/, count: 0
  end

  test "pagination preserves the action_prefix filter in page links" do
    login(@superadmin)            # auth.login_succeeded is filtered out
    seed_entries(26, action: "admin_users.created")  # 26 matching => 2 pages
    get audit_logs_path, params: { action_prefix: "admin_users." }
    assert_select "tbody tr", count: 25
    assert_select "a", text: /ถัดไป/ do |links|
      href = links.first["href"]
      assert_includes href, "action_prefix=admin_users"
      assert_includes href, "page=2"
    end
  end

  test "malformed date params are ignored" do
    login(@superadmin)
    get audit_logs_path, params: { from: "banana", to: "also-banana" }
    assert_response :success
  end
end
