module Ports
  # Contract:
  #   find(id) -> app-user record | raises Ports::NotFound (unknown/malformed uuid)
  #   list(search: nil, page: 1) -> up to PAGE_SIZE+1 users, newest first
  #   update_role(id, role:, updated_by:) -> record
  #   update_quota(id, quota:, updated_by:, mark_package: false) -> record
  # Records respond to: id, email, display_name, role, event_quota,
  # is_package_user, created_at. Soft-deleted rows are never exposed.
  module AppUserRepository
  end
end
