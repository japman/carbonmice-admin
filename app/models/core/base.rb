module Core
  # Read models over tables owned by the Go backend. Rules (spec §4):
  # explicit table_name pinned to public, no migrations, no callbacks,
  # no business logic. Writes happen ONLY in persistence adapters invoked
  # by audited domain use cases — never from controllers or views.
  class Base < ApplicationRecord
    self.abstract_class = true

    scope :kept, -> { where(deleted_at: nil) }
  end
end
