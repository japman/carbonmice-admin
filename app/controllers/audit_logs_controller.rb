class AuditLogsController < ApplicationController
  before_action -> { authorize!(:view_audit_log) }

  def index
    page = params[:page].to_i.clamp(1, 10_000)
    result = Audit::ListEntries.call(actor: current_admin, query: Persistence::ArAuditLogQuery.new,
                                     filters: filters, page: page)
    raise ApplicationController::NotAuthorized if result.failure?
    rows = result.value.to_a
    @has_next = rows.size > Persistence::ArAuditLogQuery::PAGE_SIZE
    @entries = rows.first(Persistence::ArAuditLogQuery::PAGE_SIZE)
    @page = page
  end

  private
    def filters
      {
        # actor_id has no form input yet — accepted via URL for manual forensic queries.
        actor_id: params[:actor_id].presence,
        action_prefix: params[:action_prefix].presence,
        from: params[:from].presence,
        to: params[:to].presence
      }.compact
    end
end
