module MasterData
  class CreateCarbonOffsetSource
    def self.call(actor:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      name = attrs[:name].to_s.strip
      return Result.failure("กรุณาระบุชื่อแหล่งออฟเซ็ต") if name.empty?
      return Result.failure("มีแหล่งชื่อนี้อยู่แล้ว") if repo.name_taken?(name)

      name_th_s = attrs[:name_th].to_s.strip
      name_th = name_th_s.empty? ? nil : name_th_s

      record = repo.create({ name: name, name_th: name_th }, created_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.offset_source_created", actor: actor, target: record,
                   changes: { "name" => name })
      Result.success(record)
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
