# frozen_string_literal: true

# Deletes login sessions whose updated_at is older than ADMIN_SESSION_TTL_DAYS
# (default 30). Scheduled daily via Solid Queue recurring tasks (config/recurring.yml);
# the admin:purge_sessions rake task remains for manual runs.
class PurgeSessionsJob < ApplicationJob
  queue_as :default

  def perform
    days = Integer(ENV.fetch("ADMIN_SESSION_TTL_DAYS", "30"))
    deleted = Session.older_than(days.days).delete_all
    Rails.logger.info("PurgeSessionsJob: purged #{deleted} stale session(s) older than #{days} days")
    deleted
  end
end
