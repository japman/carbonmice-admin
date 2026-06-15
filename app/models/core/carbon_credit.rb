module Core
  class CarbonCredit < Base
    self.table_name = "public.carbon_credits"
    belongs_to :user, class_name: "Core::User"
    belongs_to :carbon_offset_source, class_name: "Core::CarbonOffsetSource", optional: true
  end
end
