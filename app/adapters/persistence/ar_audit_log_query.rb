module Persistence
  class ArAuditLogQuery
    def entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, limit: 200)
      scope = AuditLog.order(created_at: :desc).limit(limit)
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where("action LIKE ?", "#{AuditLog.sanitize_sql_like(action_prefix)}%") if action_prefix.present?
      scope = scope.where(created_at: from..) if from.present?
      scope = scope.where(created_at: ..to) if to.present?
      scope
    end
  end
end
