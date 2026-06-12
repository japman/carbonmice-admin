module Persistence
  class ArEmissionFactorRepository
    PAGE_SIZE = 25

    def find(id)
      Core::EmissionFactor.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(search: nil, category_id: nil, page: 1)
      scope = Core::EmissionFactor.kept.includes(:carbon_category).order(:identifier)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("identifier ILIKE :q OR name ILIKE :q", q: q)
      end
      scope = scope.where(carbon_category_id: category_id) if category_id.present?
      page = [ page.to_i, 1 ].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def create(attrs, created_by:)
      Core::EmissionFactor.create!(**attrs, created_by: created_by)
    rescue ActiveRecord::RecordNotUnique
      raise Ports::ValidationFailed, "identifier นี้มีอยู่แล้ว"
    rescue ActiveRecord::RangeError
      raise Ports::ValidationFailed, "ค่า EF เกินขอบเขตที่อนุญาต (สูงสุด 999,999.999999)"
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation => e
      raise Ports::ValidationFailed, e.message
    end

    def update(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::RangeError
      raise Ports::ValidationFailed, "ค่า EF เกินขอบเขตที่อนุญาต (สูงสุด 999,999.999999)"
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
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
