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
      # PG int4 bound — events_quota column is integer.
      return Result.failure("โควต้าต้องไม่เกิน 2,147,483,647") if quota > 2_147_483_647

      before = repo.find(id)
      from = before.event_quota
      first_package = !before.is_package_user
      record = repo.update_quota(id, quota: quota, mark_package: first_package, updated_by: AuditIdentity.for(actor))
      changes = { "event_quota" => { "from" => from, "to" => quota } }
      changes["is_package_user"] = { "from" => false, "to" => true } if first_package
      audit.record(action: "app_users.quota_adjusted", actor: actor, target: record, changes: changes)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบผู้ใช้งาน")
    end
  end
end
