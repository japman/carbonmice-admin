class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  helper_method :can?

  private
    def can?(action)
      current_admin.present? && AdminAuth::AccessPolicy.allows?(role: current_admin.role, action: action)
    end

    def authorize!(action)
      redirect_to root_path, alert: "คุณไม่มีสิทธิ์เข้าถึงส่วนนี้" unless can?(action)
    end
end
