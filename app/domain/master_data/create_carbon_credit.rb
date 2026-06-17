module MasterData
  class CreateCarbonCredit
    def self.call(actor:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym)

      user_id = attrs[:user_id].to_s.strip
      return Result.failure("กรุณาเลือกผู้ใช้") if user_id.empty?

      amount = MasterData::TierBounds.parse_int(attrs[:carbon_credit])
      return Result.failure("จำนวน carbon credit ต้องเป็นจำนวนเต็มมากกว่า 0") if amount.nil? || amount <= 0

      source_id = attrs[:carbon_offset_source_id].to_s.strip
      return Result.failure("กรุณาเลือกแหล่งออฟเซ็ต") if source_id.empty?

      existing = repo.find_kept_by(user_id: user_id, source_id: source_id)
      if existing
        old_amount = existing.carbon_credit
        new_amount = old_amount + amount
        record = repo.update(existing.id, { carbon_credit: new_amount }, updated_by: AuditIdentity.for(actor))
        audit.record(action: "master_data.carbon_credit_updated", actor: actor, target: record,
                     changes: { "carbon_credit" => { "from" => old_amount, "to" => new_amount } })
      else
        record = repo.create(
          { user_id: user_id, carbon_credit: amount, carbon_offset_source_id: source_id },
          created_by: AuditIdentity.for(actor)
        )
        audit.record(action: "master_data.carbon_credit_created", actor: actor, target: record,
                     changes: { "user_id" => user_id, "carbon_credit" => amount })
      end
      Result.success(record)
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
