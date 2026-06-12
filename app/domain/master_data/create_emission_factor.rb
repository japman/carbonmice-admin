module MasterData
  class CreateEmissionFactor
    REQUIRED = [:identifier, :name, :source, :value_per_unit, :unit_title, :carbon_category_id].freeze
    OPTIONAL = [:description].freeze
    # Matches existing Go identifiers (ef_car_private_gasoline_km ...).
    IDENTIFIER_FORMAT = /\A[a-z0-9_.]+\z/

    def self.call(actor:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym).slice(*(REQUIRED + OPTIONAL))
      missing = REQUIRED.select { |k| attrs[k].to_s.strip.empty? }
      return Result.failure("กรอกข้อมูลไม่ครบ: #{missing.join(", ")}") unless missing.empty?
      return Result.failure("identifier ต้องเป็น a-z, 0-9, _ หรือ . เท่านั้น") unless attrs[:identifier].to_s.match?(IDENTIFIER_FORMAT)

      value = parse_positive_number(attrs[:value_per_unit])
      return Result.failure("ค่า EF ต้องเป็นตัวเลขมากกว่า 0") unless value

      record = repo.create(attrs.merge(value_per_unit: value), created_by: AuditIdentity.for(actor))
      audit.record(action: "master_data.factor_created", actor: actor, target: record,
                   changes: { "identifier" => record.identifier, "value_per_unit" => value })
      Result.success(record)
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end

    def self.parse_positive_number(raw)
      value = Float(raw)
      value.positive? ? value : nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
