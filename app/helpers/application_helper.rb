module ApplicationHelper
  ROLE_LABELS = {
    "superadmin"  => "ผู้ดูแลสูงสุด",
    "admin"       => "ผู้ดูแล",
    "viewer"      => "ผู้ชม",
    # Go-side app user roles
    "super_admin" => "ผู้ดูแลสูงสุด (ระบบหลัก)",
    "user"        => "ผู้ใช้ทั่วไป",
    "visitor"     => "ผู้เยี่ยมชม"
  }.freeze

  def role_label(role) = ROLE_LABELS.fetch(role.to_s, role.to_s)
end
