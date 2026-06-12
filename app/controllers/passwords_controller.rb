class PasswordsController < ApplicationController
  def edit
  end

  def update
    admin = current_admin
    unless admin.authenticate(params[:current_password].to_s)
      return redirect_to edit_password_path, alert: "รหัสผ่านปัจจุบันไม่ถูกต้อง"
    end
    if params[:password].to_s != params[:password_confirmation].to_s
      return redirect_to edit_password_path, alert: "รหัสผ่านใหม่กับการยืนยันไม่ตรงกัน"
    end

    if admin.update(password: params[:password])
      # Revoke every other session — a changed password invalidates old devices.
      admin.sessions.where.not(id: Current.session.id).destroy_all
      Persistence::ArAuditRecorder.new.record(action: "auth.password_changed", actor: admin,
                                              ip: request.remote_ip, user_agent: request.user_agent)
      redirect_to root_path, notice: "เปลี่ยนรหัสผ่านแล้ว"
    else
      redirect_to edit_password_path, alert: admin.errors.full_messages.to_sentence
    end
  end
end
