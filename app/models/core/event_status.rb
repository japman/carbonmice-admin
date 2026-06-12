module Core
  # Display catalog (13 rows seeded by the Go backend). events.event_status
  # stores the name_eng STRING — this table is for labels/ordering only.
  class EventStatus < Base
    self.table_name = "public.event_statuses"

    scope :ordered, -> { kept.order(:running_order) }
  end
end
