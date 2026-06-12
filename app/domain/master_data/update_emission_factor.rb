module MasterData
  class UpdateEmissionFactor
    # identifier is IMMUTABLE: the Go backend looks factors up by it.
    EDITABLE = [ :name, :description, :source, :value_per_unit, :unit_title ].freeze

    def self.call(actor:, id:, attrs:, repo:, audit:)
      return Result.failure("คุณไม่มีสิทธิ์จัดการข้อมูลหลัก") unless AdminAuth::AccessPolicy.allows?(role: actor.role, action: :manage_master_data)

      attrs = attrs.transform_keys(&:to_sym)
      unknown = attrs.keys - EDITABLE
      return Result.failure("ฟิลด์ไม่ได้รับอนุญาต: #{unknown.join(", ")}") unless unknown.empty?
      return Result.failure("ไม่มีข้อมูลให้แก้ไข") if attrs.empty?

      if attrs.key?(:value_per_unit)
        value = CreateEmissionFactor.parse_positive_number(attrs[:value_per_unit])
        return Result.failure("ค่า EF ต้องเป็นตัวเลขมากกว่า 0") unless value
        attrs[:value_per_unit] = value
      end

      before = repo.find(id)
      snapshot = attrs.keys.to_h { |k| [ k.to_s, before.public_send(k) ] }
      record = repo.update(id, attrs, updated_by: AuditIdentity.for(actor))
      diff = attrs.keys.to_h { |k| [ k.to_s, { "from" => snapshot[k.to_s], "to" => record.public_send(k) } ] }
      audit.record(action: "master_data.factor_updated", actor: actor, target: record, changes: diff)
      Result.success(record)
    rescue Ports::NotFound
      Result.failure("ไม่พบค่า EF")
    rescue Ports::ValidationFailed => e
      Result.failure(e.message)
    end
  end
end
