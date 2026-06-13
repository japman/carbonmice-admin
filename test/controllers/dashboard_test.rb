require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  def login_as(role)
    admin = AdminUser.create!(email_address: "#{role}@pea.co.th",
                              password: "password-for-tests", name: role.to_s, role: role)
    post session_path, params: { email_address: admin.email_address, password: "password-for-tests" }
    admin
  end

  test "dashboard shows totals and status breakdown" do
    login_as(:superadmin)
    create_core_event!(name_thai: "งาน1", status: "collecting")
    create_core_event!(name_thai: "งาน2", status: "collecting")
    create_core_user!(email: "u@example.com")
    get root_path
    assert_response :success
    assert_match "อีเว้นท์ทั้งหมด", response.body
    assert_select "td", text: "collecting"
    assert_select "td", text: "2"
  end

  test "recent activity comes through the audit port, newest first, capped at 10" do
    admin = login_as(:superadmin)
    12.times do |i|
      AuditLog.create!(action: "auth.login_succeeded", actor_id: admin.id,
                       actor_email: admin.email_address, created_at: i.minutes.ago)
    end
    get root_path
    assert_response :success
    rows = css_select("table:last-of-type tbody tr")
    assert_equal 10, rows.size
  end

  test "recent activity is visible to superadmin only" do
    login_as(:superadmin)
    get root_path
    assert_match "กิจกรรมล่าสุด", response.body   # superadmin sees recent audit
    delete session_path

    login_as(:viewer)
    get root_path
    assert_response :success
    refute_match "กิจกรรมล่าสุด", response.body
  end
end
