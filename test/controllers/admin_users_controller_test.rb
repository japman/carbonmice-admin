require "test_helper"

class AdminUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user, password: "password-for-tests")
    post session_path, params: { email_address: user.email_address, password: password }
  end

  test "superadmin lists, creates and updates admins with audit entries" do
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
end
