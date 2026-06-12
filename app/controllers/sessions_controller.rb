class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_url, alert: "พยายามเข้าสู่ระบบบ่อยเกินไป กรุณาลองใหม่ภายหลัง" }

  def new
  end

  def create
    admin = AdminUser.authenticate_by(email_address: params[:email_address], password: params[:password])
    if admin&.active?
      start_new_session_for(admin)
      audit_recorder.record(action: "auth.login_succeeded", actor: admin,
                            ip: request.remote_ip, user_agent: request.user_agent)
      redirect_to after_authentication_url
    else
      audit_recorder.record(action: "auth.login_failed",
                            actor_email: params[:email_address].to_s.strip.downcase,
                            ip: request.remote_ip, user_agent: request.user_agent)
      redirect_to new_session_path, alert: "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
    end
  end

  def destroy
    audit_recorder.record(action: "auth.logout", actor: current_admin,
                          ip: request.remote_ip, user_agent: request.user_agent)
    terminate_session
    redirect_to new_session_path, notice: "ออกจากระบบแล้ว"
  end

  private
    def audit_recorder = Persistence::ArAuditRecorder.new
end
