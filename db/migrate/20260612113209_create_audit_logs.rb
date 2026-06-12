class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :actor, foreign_key: { to_table: :admin_users }, null: true
      t.string   :actor_email
      t.string   :action, null: false
      t.string   :target_type
      t.string   :target_id          # string: Go-owned tables use UUID keys
      t.jsonb    :change_set, null: false, default: {}
      t.string   :ip_address
      t.string   :user_agent
      t.datetime :created_at, null: false   # insert-only: no updated_at
    end
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
