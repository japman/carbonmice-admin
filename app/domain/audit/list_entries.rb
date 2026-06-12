module Audit
  class ListEntries
    def self.call(actor:, query:, filters: {})
      return Result.failure("คุณไม่มีสิทธิ์ดูบันทึกการใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :view_audit_log)

      Result.success(query.entries(**filters))
    end
  end
end
