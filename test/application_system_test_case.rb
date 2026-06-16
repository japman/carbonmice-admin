require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # rack_test by default (fast). JS-dependent specs override with
  # `driven_by :selenium, using: :headless_chrome` per class (see EmissionFactorsTest).
  driven_by :rack_test
end
