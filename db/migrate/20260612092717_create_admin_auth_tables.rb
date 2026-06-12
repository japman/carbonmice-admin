class CreateAdminAuthTables < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_users do |t|
      t.string  :email_address, null: false, index: { unique: true }
      t.string  :password_digest, null: false
      t.string  :name, null: false
      t.integer :role, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :sessions do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
