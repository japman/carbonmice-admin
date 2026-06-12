module MasterData
  class DeleteEmissionFactor
    def self.call(actor:, id:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      record = repo.soft_delete(id, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.factor_deleted", actor: actor, target: record,
                   changes: { "identifier" => record.identifier })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบค่า EF")
    end
  end
end
