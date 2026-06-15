module Ports
  # Contract:
  #   find(id)                             -> record | raises Ports::NotFound
  #   list                                 -> [records] kept, ordered by name
  #   name_taken?(name)                    -> bool (kept sources only)
  #   create(attrs, created_by:)           -> record | raises Ports::ValidationFailed
  #   update_name_th(id, name_th, updated_by:) -> record
  #   in_use?(id)                          -> bool (any kept pricing tier references source)
  #   soft_delete(id, updated_by:)         -> record
  # name is NEVER updatable: the Go backend matches it by exact string.
  module CarbonOffsetSourceRepository
  end
end
