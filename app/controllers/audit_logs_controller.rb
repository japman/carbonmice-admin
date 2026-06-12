class AuditLogsController < ApplicationController
  before_action -> { authorize!(:view_audit_log) }

  def index
    result = Audit::ListEntries.call(actor: current_admin, query: Persistence::ArAuditLogQuery.new,
                                     filters: filters)
    raise ApplicationController::NotAuthorized if result.failure?
    @entries = result.value
    @truncated = @entries.size >= Persistence::ArAuditLogQuery::DEFAULT_LIMIT
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
