module Persistence
  class ArCategoryRepository
    def find(id)
      Core::CarbonCategory.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list = Core::CarbonCategory.kept.order(:name_eng).to_a

    def update_name_thai(id, name_thai, updated_by:)
      record = find(id)
      record.update!(name_thai: name_thai, updated_by: updated_by)
      record
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    end
  end
end
