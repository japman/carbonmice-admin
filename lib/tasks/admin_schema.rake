namespace :db do
  desc "Create the admin schema used by this app (idempotent)"
  task ensure_admin_schema: :environment do
    ActiveRecord::Base.connection.execute("CREATE SCHEMA IF NOT EXISTS admin")
  end
end

%w[db:migrate db:migrate:up db:migrate:down db:migrate:redo db:rollback db:forward].each do |task_name|
  Rake::Task[task_name].enhance(["db:ensure_admin_schema"])
end
