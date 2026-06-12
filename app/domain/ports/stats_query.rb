module Ports
  # Contract:
  #   totals -> { events:, app_users:, package_users:, factors: } (Integers, live rows)
  #   events_by_status -> [{ name_eng:, name_thai:, count: }] catalog-ordered,
  #     zero-count statuses included; statuses present on events but missing
  #     from the catalog are appended with name_thai = nil.
  module StatsQuery
  end
end
