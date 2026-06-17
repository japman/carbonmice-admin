module Persistence
  class ArCarbonCreditRepository
    PAGE_SIZE = 25

    def find(id)
      Core::CarbonCredit.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def find_kept_by(user_id:, source_id:)
      Core::CarbonCredit.kept.find_by(user_id: user_id, carbon_offset_source_id: source_id)
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def list(user_id: nil, page: 1)
      scope = Core::CarbonCredit.kept.includes(:user, :carbon_offset_source).order(created_at: :desc)
      scope = scope.where(user_id: user_id) if user_id.present?
      page = [ page.to_i, 1 ].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def create(attrs, created_by:)
      Core::CarbonCredit.create!(**attrs, created_by: created_by)
    rescue ActiveRecord::RangeError
      raise Ports::ValidationFailed, "จำนวนเกินขอบเขตที่อนุญาต"
    rescue ActiveRecord::InvalidForeignKey
      raise Ports::ValidationFailed, "ไม่พบผู้ใช้หรือแหล่งออฟเซ็ตที่เลือก"
    rescue ActiveRecord::NotNullViolation, ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.message
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::RangeError
      raise Ports::ValidationFailed, "จำนวนเกินขอบเขตที่อนุญาต"
    rescue ActiveRecord::InvalidForeignKey
      raise Ports::ValidationFailed, "ไม่พบแหล่งออฟเซ็ตที่เลือก"
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def soft_delete(id, updated_by:)
      record = find(id)
      record.update!(deleted_at: Time.current, updated_by: updated_by)
      record
    end
  end
end
