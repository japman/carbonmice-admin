require "test_helper"

class AdminUserTest < ActiveSupport::TestCase
  test "normalizes email address" do
    u = AdminUser.create!(email_address: "  Admin@PEA.co.th ",
                          password: "password-for-tests", name: "แอดมิน", role: :admin)
    assert_equal "admin@pea.co.th", u.email_address
  end

  test "rejects duplicate email case-insensitively" do
    AdminUser.create!(email_address: "a@pea.co.th", password: "password-for-tests", name: "หนึ่ง")
    dup = AdminUser.new(email_address: "A@pea.co.th", password: "password-for-tests", name: "สอง")
    refute dup.valid?
  end

  test "defaults to viewer role and active" do
    u = AdminUser.create!(email_address: "v@pea.co.th", password: "password-for-tests", name: "วิว")
    assert u.viewer?
    assert u.active?
  end

  test "rejects passwords shorter than 12 chars" do
    u = AdminUser.new(email_address: "s@pea.co.th", password: "short", name: "สั้น")
    refute u.valid?
  end

  test "rejects passwords over 72 bytes even if under 72 characters" do
    thai_password = "รหัสผ่านยาวมาก" * 2   # multibyte: > 72 bytes, < 72 chars
    u = AdminUser.new(email_address: "b@pea.co.th", password: thai_password, name: "ไบต์")
    refute u.valid?
    assert u.errors[:password].any?
  end

  test "rejects malformed email address" do
    u = AdminUser.new(email_address: "not-an-email", password: "password-for-tests", name: "ผิด")
    refute u.valid?
    assert u.errors[:email_address].any?
  end

  test "rejects blank name" do
    u = AdminUser.new(email_address: "x@pea.co.th", password: "password-for-tests", name: "")
    refute u.valid?
  end
end
