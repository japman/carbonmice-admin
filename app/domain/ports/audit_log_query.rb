module Ports
  # Contract:
  #   entries(actor_id: nil, action_prefix: nil, from: nil, to: nil, limit: 200) -> [entry]
  # Entries respond to: created_at, actor_email, action, target_type, target_id, change_set, ip_address.
  # Newest first.
  module AuditLogQuery
  end
end
