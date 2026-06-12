require "minitest/autorun"

# Standalone runs (`ruby -Itest ...`) require the domain directly — proving it
# is Rails-free. Under `bin/rails test`, Zeitwerk autoloads the same constants.
unless defined?(Rails)
  Dir[File.expand_path("../app/domain/**/*.rb", __dir__)].sort.each { |f| require f }
end
