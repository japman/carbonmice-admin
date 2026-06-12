module Ports
  # Contract:
  #   find(id) -> event record | raises Ports::NotFound (unknown OR malformed uuid)
  #   list(search: nil, status: nil, page: 1) -> up to PAGE_SIZE+1 events, newest first
  #     (the +1 row signals "has next page" to the caller)
  #   update_status(id, to:, updated_by:) -> record
  #   update_details(id, attrs, updated_by:) -> record | raises Ports::ValidationFailed
  # Records respond to: id, name_thai, name_eng, event_status, area_name,
  # province, created_by, created_at. Never exposes soft-deleted rows.
  module EventRepository
  end
end
