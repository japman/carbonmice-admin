module Ports
  # Contract:
  #   entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, page: 1) -> [entry]
  #   Returns up to PAGE_SIZE + 1 rows (the extra row signals "a next page exists").
  # Entries respond to: created_at, actor_email, action, target_type, target_id, change_set, ip_address.
  # Newest first.
  module AuditLogQuery
  end
end
