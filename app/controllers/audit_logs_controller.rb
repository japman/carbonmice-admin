class AuditLogsController < ApplicationController
  before_action -> { authorize!(:view_audit_log) }

  def index
    result = Audit::ListEntries.call(actor: current_admin, query: Persistence::ArAuditLogQuery.new,
                                     filters: filters)
    @entries = result.value
  end

  private
    def filters
      {
        actor_id: params[:actor_id].presence,
        action_prefix: params[:action_prefix].presence,
        from: params[:from].presence,
        to: params[:to].presence
      }.compact
    end
end
