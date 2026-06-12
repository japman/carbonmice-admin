require "uri"

class AdminUser < ApplicationRecord
  has_secure_password
  # Destroy sessions on delete; deactivation leaves sessions in place
  # (auth checks active? when resuming a session).
  has_many :sessions, dependent: :destroy

  # NOTE: Do NOT use #admin?, #superadmin?, or #viewer? for authorization
  # decisions. All gate checks go through AdminAuth::AccessPolicy.allows?() —
  # that is the single authority. These predicates exist because Rails
  # generates them from the enum.
  enum :role, { viewer: 0, admin: 1, superadmin: 2 }, default: :viewer

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 12 }, allow_nil: true
  validate :password_within_bcrypt_byte_limit, if: -> { password.present? }

  private

    # bcrypt hashes only the first 72 BYTES. Rails' built-in max-length check
    # counts characters, so multibyte (e.g. Thai) passwords could be silently
    # truncated without this byte-level guard.
    def password_within_bcrypt_byte_limit
      errors.add(:password, :too_long, count: 72) if password.bytesize > 72
    end
end
