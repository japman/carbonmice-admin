# First superadmin — credentials from ENV only, never hardcoded.
if ENV["SEED_SUPERADMIN_EMAIL"].present?
  user = AdminUser.find_or_create_by!(email_address: ENV["SEED_SUPERADMIN_EMAIL"]) do |u|
    u.name = ENV.fetch("SEED_SUPERADMIN_NAME", "Super Admin")
    u.password = ENV.fetch("SEED_SUPERADMIN_PASSWORD")
    u.role = :superadmin
  end
  if user.previously_new_record?
    puts "Superadmin created: #{user.email_address}"
  else
    puts "Found existing record for #{user.email_address} — role unchanged (#{user.role})"
  end
else
  puts "Skipped superadmin seed (SEED_SUPERADMIN_EMAIL not set)"
end
