require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email_address: "admin@pea.co.th",
                               password: "password-for-tests", name: "แอดมิน", role: :admin)
  end

  test "login with valid credentials reaches home" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "login with wrong password is rejected" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "wrong-password" }
    assert_redirected_to new_session_path
  end

  test "deactivated admin cannot login" do
    @admin.update!(active: false)
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    assert_redirected_to new_session_path
  end

  test "unauthenticated request is redirected to login" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "logout terminates the session" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    delete session_path
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end
end
