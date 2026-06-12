module Persistence
  class ArAdminUserRepository
    def create(email_address:, name:, password:, role:)
      AdminUser.create!(email_address:, name:, password:, role:)
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def find(id)
      AdminUser.find(id)
    rescue ActiveRecord::RecordNotFound
      raise Ports::NotFound
    end

    def update(id, **attrs)
      record = find(id)
      record.update!(**attrs)
      record
    rescue ActiveRecord::RecordInvalid => e
      raise Ports::ValidationFailed, e.record.errors.full_messages.to_sentence
    end

    def all_ordered = AdminUser.order(created_at: :desc)
  end
end
