module Events
  class UpdateDetails
    # Descriptive fields only. Everything else on events is either
    # Go-computed (quota_deducted, payment_status, snapshots) or has its
    # own audited path (event_status via Events::ChangeStatus).
    EDITABLE = [ :name_thai, :name_eng, :area_name, :province ].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการอีเว้นท์") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_events)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [ k.to_s, before.public_send(k) ] }
      record = repo.update_details(id, attrs, updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [ k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) } ] }
      audit.record(action: "events.updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบอีเว้นท์")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
