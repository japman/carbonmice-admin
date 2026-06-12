module Dashboard
  class SystemSummary
    def self.call(actor:, stats:)
      return Result.failure("คุณไม่มีสิทธิ์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :view_operations)

      Result.success(totals: stats.totals, by_status: stats.events_by_status)
    end
  end
end
