module Persistence
  class ArAuditLogQuery
    PAGE_SIZE = 25

    def entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, page: 1)
      safe_page = page.to_i.clamp(1, 10_000)
      scope = AuditLog.order(created_at: :desc)
                      .limit(PAGE_SIZE + 1)
                      .offset((safe_page - 1) * PAGE_SIZE)
      scope = scope.where(actor_id: actor_id) if actor_id.present?
      scope = scope.where("action LIKE ?", "#{AuditLog.sanitize_sql_like(action_prefix)}%") if action_prefix.present?
      if (from_date = safe_date(from))
        scope = scope.where(created_at: from_date.beginning_of_day..)
      end
      if (to_date = safe_date(to))
        scope = scope.where(created_at: ..to_date.end_of_day)
      end
      scope
    end

    private

      # Malformed ?from=/=?to= URL params are ignored rather than 500ing.
      def safe_date(value)
        value.presence&.to_date
      rescue Date::Error
        nil
      end
  end
end
