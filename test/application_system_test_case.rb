require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # rack_test: fast, no browser dependency. The app is server-rendered —
  # no JS-dependent flows yet. Swap to :selenium when they appear.
  driven_by :rack_test
end
