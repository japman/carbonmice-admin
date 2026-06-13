class HomeController < ApplicationController
  def show
    result = Dashboard::SystemSummary.call(actor: current_admin, stats: Persistence::ArStatsQuery.new)
    raise ApplicationController::NotAuthorized if result.failure?
    @totals = result.value[:totals]
    @by_status = result.value[:by_status]
    # Audit data is superadmin-only; reuse the gated audit port (returns failure for non-superadmin).
    recent = Audit::ListEntries.call(actor: current_admin,
                                     query: Persistence::ArAuditLogQuery.new,
                                     filters: { limit: 10 })
    @recent_activity = recent.success? ? recent.value : nil
  end
end
