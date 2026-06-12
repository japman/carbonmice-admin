module Persistence
  class ArOffsetPricingTierRepository
    def find(id)
      Core::CarbonOffsetPricingTier.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(source_id: nil)
      scope = Core::CarbonOffsetPricingTier.kept.order(:min_emission)
      scope = scope.where(carbon_offset_source_id: source_id) if source_id
      scope.to_a
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::StatementInvalid
      raise Ports::ValidationFailed, "ค่าขัดกับเงื่อนไขของฐานข้อมูล"
    end
  end
end
