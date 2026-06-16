require "test_helper"

class AdminUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user, password: "password-for-tests")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  test "lists admin users" do
    login(@superadmin)
    get admin_users_path
    assert_response :success
  end

  test "search filters results" do
    login(@superadmin)
    AdminUser.create!(email_address: "find_me@pea.co.th", password: "password-for-tests",
                      name: "ค้นหาได้", role: :admin)
    AdminUser.create!(email_address: "hidden@pea.co.th", password: "password-for-tests",
                      name: "ซ่อนอยู่", role: :admin)
    get admin_users_path, params: { search: "ค้นหา" }
    assert_response :success
    assert_match "find_me@pea.co.th", response.body
    assert_no_match "hidden@pea.co.th", response.body
  end

  test "creates admin via turbo_stream" do
    login(@superadmin)
    assert_difference -> { AdminUser.count } => 1,
                      -> { AuditLog.where(action: "admin_users.created").count } => 1 do
      post admin_users_path,
           params: { admin_user: { email_address: "new@pea.co.th", name: "ใหม่",
                                   password: "password-for-tests", role: "admin" } },
           as: :turbo_stream
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{prepend[^>]*target="adm_rows"}, response.body
    assert_match %r{append[^>]*target="toast_container"}, response.body
    assert_match "สร้างบัญชีผู้ดูแลแล้ว", response.body
  end

  test "creates admin via HTML — redirects" do
    login(@superadmin)
    assert_difference -> { AdminUser.count } => 1 do
      post admin_users_path, params: { admin_user: {
        email_address: "html_new@pea.co.th", name: "ใหม่ HTML", password: "password-for-tests", role: "admin" } }
    end
    assert_redirected_to admin_users_path
  end

  test "create error (duplicate email) renders new with 422" do
    login(@superadmin)
    # sa@pea.co.th already exists (created in setup)
    assert_no_difference -> { AdminUser.count } do
      post admin_users_path, params: { admin_user: {
        email_address: "sa@pea.co.th", name: "ซ้ำ", password: "password-for-tests", role: "admin" } }
    end
    assert_response :unprocessable_entity
  end

  test "updates admin via turbo_stream" do
    login(@superadmin)
    target = AdminUser.create!(email_address: "upd@pea.co.th", password: "password-for-tests",
                               name: "อัพ", role: :admin)
    assert_difference -> { AuditLog.where(action: "admin_users.updated").count } => 1 do
      patch admin_user_path(target),
            params: { admin_user: { name: "อัพใหม่", role: "viewer", active: true } },
            as: :turbo_stream
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{replace[^>]*target="#{ActionView::RecordIdentifier.dom_id(target)}"}, response.body
    assert_match %r{append[^>]*target="toast_container"}, response.body
    assert_match "บันทึกการแก้ไขแล้ว", response.body
    assert target.reload.viewer?
  end

  test "updates admin via HTML — redirects" do
    login(@superadmin)
    target = AdminUser.create!(email_address: "upd_html@pea.co.th", password: "password-for-tests",
                               name: "อัพ HTML", role: :admin)
    patch admin_user_path(target), params: { admin_user: { role: "viewer", active: false } }
    assert_redirected_to admin_users_path
    assert target.reload.viewer?
    refute target.reload.active?
  end

  test "update error (self-edit) renders edit with 422" do
    login(@superadmin)
    patch admin_user_path(@superadmin), params: { admin_user: { active: false } }
    assert_response :unprocessable_entity
    assert @superadmin.reload.active?
  end

  test "superadmin lists, creates and updates admins with audit entries — legacy HTML" do
    login(@superadmin)
    get admin_users_path
    assert_response :success

    assert_difference -> { AdminUser.count } => 1,
                      -> { AuditLog.where(action: "admin_users.created").count } => 1 do
      post admin_users_path, params: { admin_user: {
        email_address: "new@pea.co.th", name: "ใหม่", password: "password-for-tests", role: "admin" } }
    end
    assert_redirected_to admin_users_path

    target = AdminUser.find_by!(email_address: "new@pea.co.th")
    assert_difference -> { AuditLog.where(action: "admin_users.updated").count } => 1 do
      patch admin_user_path(target), params: { admin_user: { role: "viewer", active: false } }
    end
    assert target.reload.viewer?
    refute target.reload.active?
  end

  test "admin role is denied" do
    admin = AdminUser.create!(email_address: "ad@pea.co.th",
                              password: "password-for-tests", name: "แอด", role: :admin)
    login(admin)
    get admin_users_path
    assert_redirected_to root_path
  end

  test "superadmin cannot deactivate own account" do
    login(@superadmin)
    patch admin_user_path(@superadmin), params: { admin_user: { active: false } }
    assert @superadmin.reload.active?
  end

  test "self-edit guard cannot be bypassed with a zero-padded id" do
    login(@superadmin)
    patch admin_user_path(id: "0#{@superadmin.id}"), params: { admin_user: { active: false } }
    assert @superadmin.reload.active?, "padded id must not bypass the self-edit guard"
  end

  test "viewer is denied from write paths" do
    viewer = AdminUser.create!(email_address: "vw@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    assert_no_difference -> { AdminUser.count } do
      post admin_users_path, params: { admin_user: {
        email_address: "x@pea.co.th", name: "เอ็กซ์", password: "password-for-tests", role: "admin" } }
    end
    assert_redirected_to root_path
  end

  test "edit of unknown id redirects with alert" do
    login(@superadmin)
    get edit_admin_user_path(id: 999_999)
    assert_redirected_to admin_users_path
  end
end
