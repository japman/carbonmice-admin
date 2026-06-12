module Core
  class EmissionFactor < Base
    self.table_name = "public.carbon_emission_factors"

    belongs_to :carbon_category, class_name: "Core::CarbonCategory"
    belongs_to :unit, class_name: "Core::Unit", optional: true
  end
end
