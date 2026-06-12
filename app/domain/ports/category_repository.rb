module Ports
  # Contract:
  #   find(id) -> record | raises Ports::NotFound
  #   list -> all live categories
  #   update_name_thai(id, name_thai, updated_by:) -> record
  # name_eng is NEVER updatable: the Go backend matches it as an enum.
  module CategoryRepository
  end
end
