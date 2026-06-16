module Persistence
  class ArEventRepository
    PAGE_SIZE = 25

    def find(id)
      Core::Event.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      # StatementInvalid: malformed uuid strings must read as "not found",
      # not a 500 (lesson from the admin_users padded-id review).
      raise Ports::NotFound
    end

    def list(search: nil, status: nil, page: 1)
      scope = Core::Event.kept.order(created_at: :desc)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("name_thai ILIKE :q OR name_eng ILIKE :q", q: q)
      end
      scope = scope.where(event_status: status) if status.present?
      page = [ page.to_i, 1 ].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def update_status(id, to:, updated_by:)
      record = find(id)
      record.update!(event_status: to, updated_by: updated_by)
      record
    end

    def update_details(id, attrs, updated_by:)
      record = find(id)
      record.update!(**attrs, updated_by: updated_by)
      record
    rescue ActiveRecord::ValueTooLong
      raise Ports::ValidationFailed, "ข้อมูลยาวเกินขนาดที่อนุญาต (สูงสุด 255 ตัวอักษร)"
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    # Permanent delete. public.events is Go-owned with ~24 FK-RESTRICT children;
    # any referencing row makes destroy! raise InvalidForeignKey, which we surface
    # as a validation failure rather than a 500 (the row stays put).
    def hard_delete(id)
      record = find(id)
      record.destroy!
      record
    rescue ActiveRecord::InvalidForeignKey
      raise Ports::ValidationFailed, "ลบถาวรไม่ได้: อีเว้นท์นี้มีข้อมูลอื่นอ้างอิงอยู่ (เช่น การปล่อยคาร์บอน/เอกสาร)"
    end
  end
end
