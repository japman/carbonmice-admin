class HomeController < ApplicationController
  def show
    result = Dashboard::SystemSummary.call(actor: current_admin, stats: Persistence::ArStatsQuery.new)
    raise ApplicationController::NotAuthorized if result.failure?
    @totals = result.value[:totals]
    @by_status = result.value[:by_status]
    # Audit data is superadmin-only; reuse the gated audit port (returns failure for non-superadmin).
    # The port is paginated (newest first); the dashboard shows just the 10 most recent.
    recent = Audit::ListEntries.call(actor: current_admin,
                                     query: Persistence::ArAuditLogQuery.new,
                                     filters: {})
    @recent_activity = recent.success? ? recent.value.to_a.first(10) : nil
  end
end
