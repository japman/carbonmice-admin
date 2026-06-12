class AdminUser < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { viewer: 0, admin: 1, superadmin: 2 }, default: :viewer

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true
end
