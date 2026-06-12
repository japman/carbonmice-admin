module Core
  class Event < Base
    self.table_name = "public.events"

    has_many :carbon_emissions, class_name: "Core::CarbonEmission",
             foreign_key: :event_id, inverse_of: false
  end
end
