module Persistence
  class ArStatsQuery
    def totals
      {
        events: Core::Event.kept.count,
        app_users: Core::User.kept.count,
        package_users: Core::User.kept.where(is_package_user: true).count,
        factors: Core::EmissionFactor.kept.count
      }
    end

    def events_by_status
      counts = Core::Event.kept.group(:event_status).count
      catalog = Core::EventStatus.ordered.map do |s|
        { name_eng: s.name_eng, name_thai: s.name_thai, count: counts.delete(s.name_eng) || 0 }
      end
      strays = counts.map { |status, count| { name_eng: status.to_s, name_thai: nil, count: count } }
      catalog + strays
    end
  end
end
