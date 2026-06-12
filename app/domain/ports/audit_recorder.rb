module Ports
  # Contract:
  #   record(action:, actor: nil, actor_email: nil, target: nil, changes: {}, ip: nil, user_agent: nil)
  # - action: namespaced string, e.g. "auth.login_succeeded", "admin_users.created"
  # - actor: the acting admin (nil for failed logins); actor_email falls back to actor's email
  # - target: any record responding to #id (stored as string) — Go-owned rows use UUIDs
  # Raises on persistence failure: an unrecorded action must not silently succeed.
  module AuditRecorder
  end
end
