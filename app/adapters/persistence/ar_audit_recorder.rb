module Persistence
  class ArAuditRecorder
    def record(action:, actor: nil, actor_email: nil, target: nil, changes: {}, ip: nil, user_agent: nil)
      AuditLog.create!(
        actor: actor,
        actor_email: actor_email || actor&.email_address,
        action: action,
        target_type: target&.class&.name,
        target_id: target&.id&.to_s,
        change_set: changes,
        ip_address: ip,
        user_agent: user_agent
      )
    end
  end
end
