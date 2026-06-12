module MasterData
  # Shared numeric parsing + range-overlap logic for both tier types.
  module TierBounds
    INT_MAX = 2_147_483_647

    # Returns { attrs:, min:, max: } or an error String.
    def self.parse(attrs, min_key:, max_key:, price_key:, current_min:, current_max:)
      out = attrs.dup

      if attrs.key?(min_key)
        min = parse_int(attrs[min_key])
        return "ค่าต่ำสุดต้องเป็นจำนวนเต็ม 0 ถึง #{INT_MAX}" if min.nil? || min.negative? || min > INT_MAX
        out[min_key] = min
      else
        min = current_min
      end

      if attrs.key?(max_key)
        raw = attrs[max_key].to_s.strip
        if raw.empty?
          max = nil
        else
          max = parse_int(raw)
          return "ค่าสูงสุดต้องเป็นจำนวนเต็ม หรือเว้นว่าง (ไม่จำกัด)" if max.nil? || max > INT_MAX
        end
        out[max_key] = max
      else
        max = current_max
      end

      return "ค่าสูงสุดต้องมากกว่าค่าต่ำสุด" if max && max <= min

      if attrs.key?(price_key)
        price = parse_price(attrs[price_key])
        return "ราคาต้องเป็นตัวเลขตั้งแต่ 0 ขึ้นไป" if price.nil?
        out[price_key] = price
      end

      { attrs: out, min: min, max: max }
    end

    def self.overlaps?(min, max, others, min_key:, max_key:)
      hi = max || Float::INFINITY
      others.any? do |o|
        o_hi = o.public_send(max_key) || Float::INFINITY
        min <= o_hi && hi >= o.public_send(min_key)
      end
    end

    def self.parse_int(raw)
      Integer(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def self.parse_price(raw)
      value = Float(raw)
      value.negative? ? nil : value
    rescue ArgumentError, TypeError
      nil
    end
  end
end
