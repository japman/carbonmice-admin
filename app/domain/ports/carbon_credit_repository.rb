module Ports
  # Documentation-only port for carbon credit persistence.
  #
  # find(id)                           → record | raises NotFound
  # list(user_id: nil, page: 1)        → records (kept, newest first, up to PAGE_SIZE+1)
  # create(attrs, created_by:)         → record | raises ValidationFailed
  # update(id, attrs, updated_by:)     → record | raises NotFound | raises ValidationFailed
  # soft_delete(id, updated_by:)       → record | raises NotFound
  module CarbonCreditRepository
  end
end
