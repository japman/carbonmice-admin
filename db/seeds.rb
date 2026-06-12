# First superadmin — credentials from ENV only, never hardcoded.
if ENV["SEED_SUPERADMIN_EMAIL"].present?
  AdminUser.find_or_create_by!(email_address: ENV["SEED_SUPERADMIN_EMAIL"]) do |u|
    u.name = ENV.fetch("SEED_SUPERADMIN_NAME", "Super Admin")
    u.password = ENV.fetch("SEED_SUPERADMIN_PASSWORD")
    u.role = :superadmin
  end
  puts "Superadmin ensured: #{ENV["SEED_SUPERADMIN_EMAIL"]}"
else
  puts "Skipped superadmin seed (SEED_SUPERADMIN_EMAIL not set)"
end
