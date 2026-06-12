module AppUsers
  class AdjustQuota
    def self.call(actor:, id:, quota:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการผู้ใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_app_users)

      quota = begin
        Integer(quota)
      rescue ArgumentError, TypeError
        nil
      end
      return Result.failure("โควต้าต้องเป็นจำนวนเต็มตั้งแต่ 0 ขึ้นไป") if quota.nil? || quota.negative?

      before = repo.find(id)
      from = before.event_quota
      record = repo.update_quota(id, quota: quota, updated_by: AuditIdentity.for(actor))
      audit.record(action: "app_users.quota_adjusted", actor: actor, target: record,
                   changes: { "event_quota" => { "from" => from, "to" => quota } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบผู้ใช้งาน")
    end
  end
end
