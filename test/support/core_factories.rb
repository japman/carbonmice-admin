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
    scope_id = conn.select_value(
      "INSERT INTO public.carbon_scopes (name, created_by) VALUES ('scope_1', 'test') RETURNING id"
    )
    category_id = conn.select_value(sanitize_sql(
      "INSERT INTO public.carbon_categories (name_thai, name_eng, carbon_scope_id, created_by)
       VALUES (?, ?, ?, 'test') RETURNING id", category_thai, category_eng, scope_id
    ))
    unit_id = conn.select_value(
      "INSERT INTO public.units (code, multiplier, created_by) VALUES ('kg', 1, 'test') RETURNING id"
    )
    conn.select_value(sanitize_sql(
      "INSERT INTO public.carbon_emissions (event_id, carbon_category_id, unit_id, pre_event_emission, post_event_emission, created_by)
       VALUES (?, ?, ?, ?, ?, 'test') RETURNING id",
      event_id, category_id, unit_id, pre, post
    ))
  end

  private

    def sanitize_sql(sql, *binds)
      ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
    end
end
