class ChangeAuditLogsActorFkToNullify < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :audit_logs, column: :actor_id
    add_foreign_key :audit_logs, :admin_users, column: :actor_id, on_delete: :nullify
  end
end
