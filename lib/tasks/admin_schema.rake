namespace :db do
  desc "Create the admin schema used by this app (idempotent)"
  task ensure_admin_schema: :environment do
    ActiveRecord::Base.connection.execute("CREATE SCHEMA IF NOT EXISTS admin")
  end
end

Rake::Task["db:migrate"].enhance(["db:ensure_admin_schema"])
