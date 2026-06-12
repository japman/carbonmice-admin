module Core
  class CarbonEmission < Base
    self.table_name = "public.carbon_emissions"

    belongs_to :carbon_category, class_name: "Core::CarbonCategory"
    belongs_to :unit, class_name: "Core::Unit"
  end
end
