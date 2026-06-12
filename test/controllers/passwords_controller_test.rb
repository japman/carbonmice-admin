require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email_address: "me@pea.co.th",
                               password: "password-for-tests", name: "ฉัน", role: :admin)
    post session_path, params: { email_address: "me@pea.co.th", password: "password-for-tests" }
  end

  test "changes password with correct current password and audits" do
    get edit_password_path
    assert_response :success
    assert_difference -> { AuditLog.where(action: "auth.password_changed").count } => 1 do
      patch password_path, params: { current_password: "password-for-tests",
                                     password: "a-brand-new-password",
                                     password_confirmation: "a-brand-new-password" }
    end
    assert_redirected_to root_path
    assert AdminUser.authenticate_by(email_address: "me@pea.co.th", password: "a-brand-new-password")
  end

  test "wrong current password is rejected without audit" do
    assert_no_difference -> { AuditLog.count } do
      patch password_path, params: { current_password: "wrong-password!",
                                     password: "a-brand-new-password",
                                     password_confirmation: "a-brand-new-password" }
    end
    assert_redirected_to edit_password_path
    assert AdminUser.authenticate_by(email_address: "me@pea.co.th", password: "password-for-tests")
  end

  test "mismatched confirmation and short password are rejected" do
    patch password_path, params: { current_password: "password-for-tests",
                                   password: "a-brand-new-password",
                                   password_confirmation: "different" }
    assert_redirected_to edit_password_path

    patch password_path, params: { current_password: "password-for-tests",
                                   password: "short", password_confirmation: "short" }
    assert_redirected_to edit_password_path
    assert AdminUser.authenticate_by(email_address: "me@pea.co.th", password: "password-for-tests")
  end

  test "changing password revokes other sessions" do
    other = Session.create!(admin_user: @admin, ip_address: "10.0.0.9", user_agent: "other-device")
    patch password_path, params: { current_password: "password-for-tests",
                                   password: "a-brand-new-password",
                                   password_confirmation: "a-brand-new-password" }
    refute Session.exists?(other.id)
    get root_path
    assert_response :success   # current session survives
  end
end
