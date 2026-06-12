module MasterData
  class RenameCategory
    # ONLY the Thai display label is editable. name_eng is a Go enum value.
    def self.call(actor:, id:, name_thai:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      name_thai = name_thai.to_s.strip
      return Result.failure("ชื่อภาษาไทยห้ามว่าง") if name_thai.empty?

      before = repo.find(id)
      from = before.name_thai
      record = repo.update_name_thai(id, name_thai, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.category_renamed", actor: actor, target: record,
                   changes: { "name_thai" => { "from" => from, "to" => name_thai } })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบหมวดหมู่")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
