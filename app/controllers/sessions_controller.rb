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
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, notice: "ออกจากระบบแล้ว"
  end
end
