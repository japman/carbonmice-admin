module MasterData
  class UpdateCarbonCredit
    EDITABLE = [ :carbon_credit, :carbon_offset_source_id ].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      if attrs.key?(:carbon_credit)
        amount = MasterData::TierBounds.parse_int(attrs[:carbon_credit])
        return Result.failure("จำนวน carbon credit ต้องเป็นจำนวนเต็มมากกว่า 0") if amount.nil? || amount <= 0
        attrs[:carbon_credit] = amount
      end

      if attrs.key?(:carbon_offset_source_id)
        attrs[:carbon_offset_source_id] = attrs[:carbon_offset_source_id].to_s.empty? ? nil : attrs[:carbon_offset_source_id]
      end

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [ k.to_s, before.public_send(k) ] }
      record = repo.update(id, attrs, updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [ k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) } ] }
      audit.record(action: "master_data.carbon_credit_updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบ carbon credit")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
