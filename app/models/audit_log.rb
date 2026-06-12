class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "AdminUser", optional: true

  validates :action, presence: true

  # Insert-only: the application has no path to rewrite history.
  # NOTE: readonly? does NOT block AuditLog.delete(id), .delete_all, .update_all,
  # or raw connection.execute — those must never appear in this codebase.
  # DB-level hardening (REVOKE UPDATE/DELETE on admin.audit_logs from the app
  # role) is deferred to Plan 3 (deployment hardening) alongside least-privilege grants.
  def readonly? = persisted?
end
