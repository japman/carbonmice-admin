module Ports
  # Two adapters share this contract shape (event tiers have no source scope):
  #   find(id) -> record | raises Ports::NotFound
  #   list(source_id: nil) -> all live tiers (event tiers ignore source_id)
  #   update(id, attrs, updated_by:) -> record
  # Event tier records: min_participants, max_participants (nil = open), price_per_person.
  # Offset tier records: min_emission, max_emission (nil = open), price_per_emission,
  # carbon_offset_source_id.
  module PricingTierRepositories
  end
end
