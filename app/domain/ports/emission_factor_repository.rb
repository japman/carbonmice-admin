module Ports
  # Contract:
  #   find(id) -> record | raises Ports::NotFound (unknown/malformed uuid/soft-deleted)
  #   list(search: nil, category_id: nil, page: 1) -> up to PAGE_SIZE+1 records
  #   create(attrs, created_by:) -> record | raises Ports::ValidationFailed (dup identifier, too long)
  #   update(id, attrs, updated_by:) -> record | raises Ports::ValidationFailed
  #   soft_delete(id, updated_by:) -> record
  # Records respond to: id, identifier, name, description, source,
  # value_per_unit, unit_title, carbon_category_id, created_by.
  module EmissionFactorRepository
  end
end
