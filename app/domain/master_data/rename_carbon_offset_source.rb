module MasterData
  class RenameCarbonOffsetSource
    # Only name_th (Thai display label) is editable. name is LOCKED — Go backend matches it by string.
    def self.call(actor:, id:, name_th:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      name_th_s = name_th.to_s.strip
      name_th = name_th_s.empty? ? nil : name_th_s  # blank -> nil, which is ALLOWED

      before = repo.find(id)
      from = before.name_th
      record = repo.update_name_th(id, name_th, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.offset_source_renamed", actor: actor, target: record,
                   changes: { "name_th" => { "from" => from, "to" => name_th } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบแหล่งออฟเซ็ต")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
