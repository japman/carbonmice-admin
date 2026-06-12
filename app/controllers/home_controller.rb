class HomeController < ApplicationController
  def show
    result = Dashboard::SystemSummary.call(actor: current_admin, stats: Persistence::ArStatsQuery.new)
    raise ApplicationController::NotAuthorized if result.failure?
    @totals = result.value[:totals]
    @by_status = result.value[:by_status]
    # Audit data is superadmin-only (same gate as the audit page).
    @recent_activity = can?(:view_audit_log) ? AuditLog.order(created_at: :desc).limit(10) : nil
  end
end
