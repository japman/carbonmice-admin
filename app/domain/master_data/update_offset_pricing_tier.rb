module MasterData
  class UpdateOffsetPricingTier
    EDITABLE = [ :min_emission, :max_emission, :price_per_emission ].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      repo.advisory_lock!
      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      before = repo.find(id)
      parsed = TierBounds.parse(attrs,
                                min_key: :min_emission, max_key: :max_emission,
                                price_key: :price_per_emission,
                                current_min: before.min_emission,
                                current_max: before.max_emission)
      return Result.failure(parsed) if parsed.is_a?(String)

      others = repo.list(source_id: before.carbon_offset_source_id).reject { |t| t.id == before.id }
      if TierBounds.overlaps?(parsed[:min], parsed[:max], others,
                              min_key: :min_emission, max_key: :max_emission)
        return Result.failure("ช่วงปริมาณคาร์บอนทับซ้อนกับระดับราคาอื่นในแหล่งเดียวกัน")
      end

      snapshot = attrs.keys.to_h { |k| [ k.to_s, before.public_send(k) ] }
      record = repo.update(id, parsed[:attrs], updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [ k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) } ] }
      audit.record(action: "master_data.offset_tier_updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบระดับราคา")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
