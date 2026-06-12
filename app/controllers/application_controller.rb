class ApplicationController < ActionController::Base
  class NotAuthorized < StandardError; end

  include Authentication
  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :can?

  rescue_from NotAuthorized do
    redirect_to root_path, alert: "คุณไม่มีสิทธิ์เข้าถึงส่วนนี้"
  end

  private
    def can?(action)
      current_admin.present? && AdminAuth::AccessPolicy.allows?(role: current_admin.role, action: action)
    end

    # Raises so it halts wherever it is called — before_action or action body.
    def authorize!(action)
      raise NotAuthorized unless can?(action)
    end
end
