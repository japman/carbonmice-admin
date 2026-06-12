module AppUsers
  class ChangeRole
    # Role strings used by the Go backend (internal user model).
    ROLES = [ "user", "admin", "super_admin" ].freeze

    def self.call(actor:, id:, role:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการผู้ใช้งาน") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_app_users)
      role = role.to_s
      return Result.failure("สิทธิ์ไม่ถูกต้อง") unless ROLES.include?(role)

      before = repo.find(id)
      from = before.role
      record = repo.update_role(id, role: role, updated_by: AuditIdentity.for(actor))
      audit.record(action: "app_users.role_changed", actor: actor, target: record,
                   changes: { "role" => { "from" => from, "to" => role } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบผู้ใช้งาน")
    end
  end
end
