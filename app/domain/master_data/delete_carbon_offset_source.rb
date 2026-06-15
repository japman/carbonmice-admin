module MasterData
  class DeleteCarbonOffsetSource
    def self.call(actor:, id:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)
      return Result.failure("ลบไม่ได้: มีระดับราคา offset ที่อ้างอิงแหล่งนี้อยู่") if repo.in_use?(id)

      record = repo.soft_delete(id, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.offset_source_deleted", actor: actor, target: record,
                   changes: { "name" => record.name })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบแหล่งออฟเซ็ต")
    end
  end
end
