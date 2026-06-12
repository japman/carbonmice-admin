module AdminAuth
  class CreateAdmin
    def self.call(actor:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการบัญชีผู้ดูแล") unless AccessPolicy.allows?(role: actor.role, action: :manage_admin_users)

      record = repo.create(**attrs)
      audit.record(action: "admin_users.created", actor: actor, target: record,
                   changes: { "email_address" => record.email_address, "role" => record.role })
      Result.success(record)
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
