namespace :admin do
  desc "Delete login sessions not updated within ADMIN_SESSION_TTL_DAYS (default 30)"
  task purge_sessions: :environment do
    days = Integer(ENV.fetch("ADMIN_SESSION_TTL_DAYS", "30"))
    deleted = Session.older_than(days.days).delete_all
    puts "Purged #{deleted} stale session(s) older than #{days} days."
  end
end
