module Persistence
  class ArEventPricingTierRepository
    def find(id)
      Core::EventPricingTier.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(source_id: nil)
      Core::EventPricingTier.kept.order(:min_participants).to_a
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::StatementInvalid => e
      # DB CHECK constraints (max > 0 AND >= min) are the last line of defense.
      raise Ports::ValidationFailed, "ค่าขัดกับเงื่อนไขของฐานข้อมูล"
    end
  end
end
