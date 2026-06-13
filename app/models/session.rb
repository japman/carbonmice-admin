class Session < ApplicationRecord
  belongs_to :admin_user

  # Sessions never expire on their own; the admin:purge_sessions task sweeps stale rows.
  scope :older_than, ->(age) { where(updated_at: ..age.ago) }
end
