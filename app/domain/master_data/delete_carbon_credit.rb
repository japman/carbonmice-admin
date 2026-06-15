module MasterData
  class DeleteCarbonCredit
    def self.call(actor:, id:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      record = repo.soft_delete(id, updated_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.carbon_credit_deleted", actor: actor, target: record,
                   changes: { "carbon_credit" => record.carbon_credit })
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบ carbon credit")
    end
  end
end
