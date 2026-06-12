class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "AdminUser", optional: true

  validates :action, presence: true

  # Insert-only: the application has no path to rewrite history.
  def readonly? = persisted?
end
