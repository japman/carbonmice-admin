module Persistence
  class ArAppUserRepository
    PAGE_SIZE = 25

    def find(id)
      Core::User.kept.find(id)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid
      raise Ports::NotFound
    end

    def list(search: nil, page: 1)
      scope = Core::User.kept.order(created_at: :desc)
      if search.present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
        scope = scope.where("email ILIKE :q OR display_name ILIKE :q", q: q)
      end
      page = [ page.to_i, 1 ].max
      scope.limit(PAGE_SIZE + 1).offset((page - 1) * PAGE_SIZE)
    end

    def update_role(id, role:, updated_by:)
      record = find(id)
      record.update!(role: role, updated_by: updated_by)
      record
    end

    def update_quota(id, quota:, updated_by:, mark_package: false)
      record = find(id)
      attrs = { event_quota: quota, updated_by: updated_by }
      attrs[:is_package_user] = true if mark_package
      record.update!(**attrs)
      record
    end
  end
end
