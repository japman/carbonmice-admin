module Audit
  class ListEntries
    def self.call(actor:, query:, filters: {}, page: 1)
      return Result.failure("คุณไม่มีสิทธิ์ดูบันทึกการใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :view_audit_log)

      Result.success(query.entries(**filters, page: page))
    end
  end
end
