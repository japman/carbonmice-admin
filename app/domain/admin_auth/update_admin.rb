module AdminAuth
  class UpdateAdmin
    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการบัญชีผู้ดูแล") unless AccessPolicy.allows?(role: actor.role, action: :manage_admin_users)
      return Result.failure("ไม่สามารถปิดหรือลดสิทธิ์บัญชีของตัวเองได้") if actor.id.to_s == id.to_s

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [k.to_s, before.public_send(k)] }
      record = repo.update(id, **attrs)
      diff = attrs.keys.to_h { |k| [k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) }] }
      audit.record(action: "admin_users.updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบบัญชีผู้ดูแล")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
