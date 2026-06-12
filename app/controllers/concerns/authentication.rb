module Authentication
  extend ActiveSupport::Concern

  SESSION_LIFETIME = 30.days

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_admin
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated? = resume_session.present?

    def current_admin = Current.admin_user

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return nil unless (id = cookies.signed[:session_id])
      session = Session.includes(:admin_user).find_by(id: id)
      return nil unless session&.admin_user&.active?
      return nil if session.created_at < SESSION_LIFETIME.ago
      session
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(admin_user)
      admin_user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |new_session|
        Current.session = new_session
        cookies.signed[:session_id] = { value: new_session.id, httponly: true, same_site: :lax, expires: SESSION_LIFETIME.from_now }
      end
    end

    def terminate_session
      Current.session&.destroy
      cookies.delete(:session_id)
      Current.session = nil
    end
end
