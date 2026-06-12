# Keep the SQL structure dump limited to the schema this app owns.
# The shared `public` schema belongs to the Go backend and must never
# appear in this repo's structure.sql.
#
# Rails 8 auto-appends --schema=<x> for every entry in schema_search_path, so
# we also pass --exclude-schema=public to guarantee public is suppressed even
# when the search path includes it (pg_dump: exclusion beats inclusion).
ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = [ "--schema=admin", "--exclude-schema=public" ]
