module Persistence
  class ArAuditLogQuery
    DEFAULT_LIMIT = 200

    def entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, limit: DEFAULT_LIMIT)
      scope = AuditLog.order(created_at: :desc).limit(limit)
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where("action LIKE ?", "#{AuditLog.sanitize_sql_like(action_prefix)}%") if action_prefix.present?
      scope = scope.where(created_at: from.to_date.beginning_of_day..) if from.present?
      scope = scope.where(created_at: ..to.to_date.end_of_day) if to.present?
      scope
    end
  end
end
