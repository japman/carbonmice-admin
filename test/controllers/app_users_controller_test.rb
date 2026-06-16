require "test_helper"

class AppUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists and searches app users" do
    login(@superadmin)
    create_core_user!(email: "somchai@example.com", display_name: "สมชาย")
    create_core_user!(email: "other@example.com", display_name: "คนอื่น")
    get app_users_path
    assert_response :success
    assert_select "td", text: "somchai@example.com"
    get app_users_path, params: { search: "สมชาย" }
    assert_select "td", text: "somchai@example.com"
    assert_select "td", text: "other@example.com", count: 0
  end

  test "updates role and quota with audit entries — turbo_stream" do
    login(@superadmin)
    user = create_core_user!(email: "t@example.com", role: "user", quota: 1)
    assert_difference -> { AuditLog.where(action: "app_users.role_changed").count } => 1,
                      -> { AuditLog.where(action: "app_users.quota_adjusted").count } => 1 do
      patch app_user_path(user.id),
            params: { app_user: { role: "admin", event_quota: "9" } },
            as: :turbo_stream
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{replace[^>]*target="#{ActionView::RecordIdentifier.dom_id(user)}"}, response.body
    assert_match %r{append[^>]*target="toast_container"}, response.body
    assert_match "บันทึกการแก้ไขแล้ว", response.body
    user.reload
    assert_equal "admin", user.role
    assert_equal 9, user.event_quota
  end

  test "updates role and quota — HTML redirect" do
    login(@superadmin)
    user = create_core_user!(email: "thtml@example.com", role: "user", quota: 1)
    patch app_user_path(user.id), params: { app_user: { role: "admin", event_quota: "5" } }
    assert_redirected_to app_users_path
    assert_equal "admin", user.reload.role
  end

  test "unchanged values do not produce audit noise" do
    login(@superadmin)
    user = create_core_user!(email: "same@example.com", role: "user", quota: 4)
    assert_no_difference -> { AuditLog.count } do
      patch app_user_path(user.id), params: { app_user: { role: "user", event_quota: "4" } }
    end
  end

  test "invalid role renders edit with 422" do
    login(@superadmin)
    user = create_core_user!(email: "bad@example.com", role: "user", quota: 0)
    patch app_user_path(user.id), params: { app_user: { role: "invalid_role", event_quota: "0" } }
    assert_response :unprocessable_entity
  end

  test "edit preselects an out-of-list role without demoting it" do
    login(@superadmin)
    user = create_core_user!(email: "vis@example.com", role: "visitor", quota: 1)
    get edit_app_user_path(user.id)
    assert_response :success
    assert_select "select[name='app_user[role]'] option[selected][value='visitor']"
    # quota-only save must not change the role
    patch app_user_path(user.id), params: { app_user: { role: "visitor", event_quota: "2" } }
    assert_equal "visitor", user.reload.role
    assert_equal 2, user.reload.event_quota
  end

  test "viewer can read but not write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    user = create_core_user!(email: "ro@example.com")
    get app_users_path
    assert_response :success
    patch app_user_path(user.id), params: { app_user: { role: "admin" } }
    assert_redirected_to root_path
    assert_equal "user", user.reload.role
  end
end
