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
    assert_difference -> { AuditLog.where(action: "auth.login_failed").count } do
      post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    end
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

  test "deactivation mid-session locks the admin out on next request" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    get root_path
    assert_response :success
    @admin.update!(active: false)
    get root_path
    assert_redirected_to new_session_path
  end

  test "sessions older than 30 days are rejected" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    @admin.sessions.last.update!(created_at: 31.days.ago)
    get root_path
    assert_redirected_to new_session_path
  end

  test "successful login writes an audit entry" do
    assert_difference -> { AuditLog.where(action: "auth.login_succeeded").count } do
      post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    end
    assert_equal @admin.id, AuditLog.where(action: "auth.login_succeeded").order(:id).last.actor_id
  end

  test "failed login writes an audit entry with the attempted email" do
    assert_difference -> { AuditLog.where(action: "auth.login_failed").count } do
      post session_path, params: { email_address: "Nobody@pea.co.th", password: "wrong-password" }
    end
    assert_equal "nobody@pea.co.th", AuditLog.where(action: "auth.login_failed").order(:id).last.actor_email
  end

  test "logout writes an audit entry" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    assert_difference -> { AuditLog.where(action: "auth.logout").count } do
      delete session_path
    end
  end

  test "logout succeeds even when audit recording fails" do
    post session_path, params: { email_address: "admin@pea.co.th", password: "password-for-tests" }
    raising_recorder = Object.new
    def raising_recorder.record(**) = raise(ActiveRecord::ActiveRecordError, "audit down")
    original_new = Persistence::ArAuditRecorder.method(:new)
    Persistence::ArAuditRecorder.define_singleton_method(:new) { raising_recorder }
    begin
      delete session_path
    ensure
      Persistence::ArAuditRecorder.define_singleton_method(:new, &original_new)
    end
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path   # session truly terminated
  end
end
