class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :admin_user, to: :session, allow_nil: true
end
