# Builders for rows in the Go-owned public schema (TEST DATABASE ONLY).
# Raw SQL on purpose: the app has no write path that INSERTs into public,
# and we keep it that way — these helpers must never leak into app code.
module CoreFactories
  def create_core_event!(name_thai: "งานทดสอบ", name_eng: "Test Event", status: "draft",
                         area_name: nil, province: nil, created_by: "test-user")
    conn = ActiveRecord::Base.connection
    type_id = conn.select_value(
      "INSERT INTO public.event_types (name, created_by) VALUES ('ทดสอบ', 'test') RETURNING id"
    )
    template_id = conn.select_value(sanitize_sql(
      "INSERT INTO public.event_templates (name, license_fee, created_by, event_type_id)
       VALUES ('เทมเพลตทดสอบ', 0, 'test', ?) RETURNING id", type_id
    ))
    event_id = conn.select_value(sanitize_sql(
      "INSERT INTO public.events (name_thai, name_eng, event_status, area_name, province, created_by, event_template_id)
       VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id",
      name_thai, name_eng, status, area_name, province, created_by, template_id
    ))
    Core::Event.find(event_id)
  end

  def create_core_user!(email:, role: "user", quota: 0, display_name: "ผู้ใช้ทดสอบ",
                        package: false, raw_id: SecureRandom.uuid)
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.users (raw_id, email, role, event_quota, is_package_user, display_name, created_by)
       VALUES (?, ?, ?, ?, ?, ?, 'test') RETURNING id",
      raw_id, email, role, quota, package, display_name
    ))
    Core::User.find(id)
  end

  # Returns the new row's UUID string (no Core::CarbonEmission write model
  # exists — emissions are read via Core::CarbonEmission in app code only).
  def create_core_emission!(event_id:, category_eng: "travel", category_thai: "การเดินทาง", pre: 10.5, post: nil)
    conn = ActiveRecord::Base.connection
    category_id = create_core_category!(name_thai: category_thai, name_eng: category_eng)
    unit_id = create_core_unit!
    conn.select_value(sanitize_sql(
      "INSERT INTO public.carbon_emissions (event_id, carbon_category_id, unit_id, pre_event_emission, post_event_emission, created_by)
       VALUES (?, ?, ?, ?, ?, 'test') RETURNING id",
      event_id, category_id, unit_id, pre, post
    ))
  end

  def create_core_emission_factor!(identifier:, name: "ค่าทดสอบ", value: 1.5,
                                   source: "TGO", unit_title: "kgCO2e/unit", category_id: nil)
    category_id ||= create_core_category!
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.carbon_emission_factors
         (name, source, value_per_unit, unit_title, identifier, carbon_category_id, created_by)
       VALUES (?, ?, ?, ?, ?, ?, 'test') RETURNING id",
      name, source, value, unit_title, identifier, category_id
    ))
    Core::EmissionFactor.find(id)
  end

  def create_core_event_pricing_tier!(min:, max:, price:)
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.event_pricing_tiers
         (min_participants, max_participants, price_per_person, created_by)
       VALUES (?, ?, ?, 'test') RETURNING id", min, max, price
    ))
    Core::EventPricingTier.find(id)
  end

  def create_core_offset_source!(name: "Test Source", name_th: nil)
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.carbon_offset_sources (name, name_th, created_by)
       VALUES (?, ?, 'test') RETURNING id", name, name_th
    ))
    Core::CarbonOffsetSource.find(id)
  end

  def create_core_offset_tier!(source_id:, min:, max:, price:, unit_id: nil)
    unit_id ||= create_core_unit!
    id = ActiveRecord::Base.connection.select_value(sanitize_sql(
      "INSERT INTO public.carbon_offset_pricing_tiers
         (min_emission, max_emission, price_per_emission, unit_id, carbon_offset_source_id, created_by)
       VALUES (?, ?, ?, ?, ?, 'test') RETURNING id", min, max, price, unit_id, source_id
    ))
    Core::CarbonOffsetPricingTier.find(id)
  end

  private

    # carbon_scopes.name CHECK: scope_1|scope_2|scope_3
    def create_core_category!(name_thai: "หมวดทดสอบ", name_eng: "test_category")
      conn = ActiveRecord::Base.connection
      scope_id = conn.select_value(
        "INSERT INTO public.carbon_scopes (name, created_by) VALUES ('scope_1', 'test') RETURNING id"
      )
      conn.select_value(sanitize_sql(
        "INSERT INTO public.carbon_categories (name_thai, name_eng, carbon_scope_id, created_by)
         VALUES (?, ?, ?, 'test') RETURNING id", name_thai, name_eng, scope_id
      ))
    end

    def create_core_unit!(code: "kg", multiplier: 1)
      ActiveRecord::Base.connection.select_value(sanitize_sql(
        "INSERT INTO public.units (code, multiplier, created_by) VALUES (?, ?, 'test') RETURNING id",
        code, multiplier
      ))
    end

    def sanitize_sql(sql, *binds)
      ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
    end
end
