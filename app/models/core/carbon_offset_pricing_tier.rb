module Core
  class CarbonOffsetPricingTier < Base
    self.table_name = "public.carbon_offset_pricing_tiers"

    belongs_to :carbon_offset_source, class_name: "Core::CarbonOffsetSource"
    belongs_to :unit, class_name: "Core::Unit"
  end
end
