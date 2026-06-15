module Persistence
  class ArCarbonOffsetSourceRepository
    def find(id)
      Core::CarbonOffsetSource.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list = Core::CarbonOffsetSource.kept.order(:name).to_a

    def name_taken?(name)
      Core::CarbonOffsetSource.kept.where(name: name).exists?
    end

    def create(attrs, created_by:)
      Core::CarbonOffsetSource.create!(**attrs, created_by: created_by)
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::NotNullViolation, ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.message
    end

    def update_name_th(id, name_th, updated_by:)
      record = find(id)
      record.update!(name_th: name_th, updated_by: updated_by)
      record
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def in_use?(id)
      Core::CarbonOffsetPricingTier.kept.where(carbon_offset_source_id: id).exists?
    end

    def soft_delete(id, updated_by:)
      record = find(id)
      record.update!(deleted_at: Time.current, updated_by: updated_by)
      record
    end
  end
end
