module Ports
  # Contract:
  #   create(email_address:, name:, password:, role:) -> record (responds to id/email_address/name/role/active)
  #   find(id) -> record | raises Ports::NotFound
  #   update(id, **attrs) -> record | raises Ports::NotFound, Ports::ValidationFailed
  #   all_ordered -> [record] newest first
  module AdminUserRepository
  end
end
