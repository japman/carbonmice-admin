# Ports are duck-typed interfaces between the domain and adapters.
# Each port module documents its contract; adapters implement it.
module Ports
  class Error < StandardError; end
  class NotFound < Error; end
  class ValidationFailed < Error; end
end
