ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Load the Go backend's table structure (public schema) into the test DB once.
# db/core_structure.sql is a fixture dumped from the dev DB — see README.
connection = ActiveRecord::Base.connection
unless connection.data_source_exists?("public.events")
  raise "core_structure.sql must only load in the test environment" unless Rails.env.test?

  # BEGIN/COMMIT makes the load atomic (Postgres DDL is transactional):
  # a failed load leaves no partial schema behind the idempotency guard.
  connection.raw_connection.exec("BEGIN;\n#{File.read(File.expand_path("../db/core_structure.sql", __dir__))}\nCOMMIT;")
  # pg_dump pins search_path to '' for the session — restore ours.
  connection.execute("SET search_path TO admin, public")
end

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

module ActiveSupport
  class TestCase
    # pg 1.6.3 segfaults in forked parallel workers under Ruby 4.0.0.
    # Re-enable (workers: :number_of_processors) once the pg gem fixes it.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include CoreFactories

    # Add more helper methods to be used by all tests here...
  end
end
