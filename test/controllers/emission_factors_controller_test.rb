require "test_helper"

class EmissionFactorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists and searches factors with the Go-restart warning" do
    login(@superadmin)
    create_core_emission_factor!(identifier: "ef_visible", name: "มองเห็น")
    get emission_factors_path
    assert_response :success
    assert_select "td", text: "ef_visible"
    assert_match "ระบบหลัก", response.body   # restart warning banner
    get emission_factors_path, params: { search: "ไม่มีทาง" }
    assert_select "td", text: "ef_visible", count: 0
  end

  test "creates, edits and deletes a factor with audit entries" do
    login(@superadmin)
    category_id = create_core_emission_factor!(identifier: "ef_for_cat").carbon_category_id

    assert_difference -> { AuditLog.where(action: "master_data.factor_created").count } => 1 do
      post emission_factors_path, params: { emission_factor: {
        identifier: "ef_created_via_web", name: "เว็บ", source: "TGO", value_per_unit: "1.5",
        unit_title: "kgCO2e/kg", carbon_category_id: category_id } }
    end
    assert_redirected_to emission_factors_path
    factor = Core::EmissionFactor.find_by!(identifier: "ef_created_via_web")

    get edit_emission_factor_path(factor.id)
    assert_response :success
    assert_select "input[name='emission_factor[identifier]'][disabled]"

    assert_difference -> { AuditLog.where(action: "master_data.factor_updated").count } => 1 do
      patch emission_factor_path(factor.id), params: { emission_factor: { value_per_unit: "2.0" } }
    end
    assert_equal 2.0, factor.reload.value_per_unit.to_f

    assert_difference -> { AuditLog.where(action: "master_data.factor_deleted").count } => 1 do
      delete emission_factor_path(factor.id)
    end
    assert factor.reload.deleted_at.present?
  end

  test "create error re-renders new with submitted values and no redirect" do
    login(@superadmin)
    create_core_emission_factor!(identifier: "ef_dup")
    category_id = Core::CarbonCategory.kept.first.id
    assert_no_difference -> { Core::EmissionFactor.kept.count } do
      post emission_factors_path, params: { emission_factor: {
        identifier: "ef_dup", name: "ชื่อที่พิมพ์ไว้", source: "TGO",
        description: "คำอธิบายที่พิมพ์",
        value_per_unit: "2.5", unit_title: "kgCO2e/kg", carbon_category_id: category_id } }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='emission_factor[name]'][value='ชื่อที่พิมพ์ไว้']"
    assert_select "input[name='emission_factor[identifier]'][value='ef_dup']"
    assert_select "textarea[name='emission_factor[description]']", text: "คำอธิบายที่พิมพ์"
  end

  test "update error re-renders edit with submitted value and no redirect" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_edit_err", value: 1.5)
    patch emission_factor_path(f.id), params: { emission_factor: { value_per_unit: "-3" } }
    assert_response :unprocessable_entity
    assert_select "input[name='emission_factor[value_per_unit]'][value='-3']"
    assert_equal 1.5, f.reload.value_per_unit.to_f
  end

  test "viewer reads but cannot write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    f = create_core_emission_factor!(identifier: "ef_ro")
    get emission_factors_path
    assert_response :success
    patch emission_factor_path(f.id), params: { emission_factor: { value_per_unit: "9" } }
    assert_redirected_to root_path
    assert_equal 1.5, f.reload.value_per_unit.to_f
  end

  test "create via turbo_stream prepends a row, closes the modal, and toasts" do
    login(@superadmin)
    category_id = create_core_category!
    assert_difference -> { Core::EmissionFactor.kept.count } => 1 do
      post emission_factors_path, as: :turbo_stream, params: { emission_factor: {
        identifier: "ef_stream", name: "n", source: "s", value_per_unit: "1.0",
        unit_title: "kg", description: "", carbon_category_id: category_id } }
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="prepend" target="ef_rows"}, response.body
    assert_match %r{turbo-stream action="update" target="modal"}, response.body
    assert_match %r{turbo-stream action="append" target="toast_container"}, response.body
  end

  test "create via HTML still redirects (no-JS fallback)" do
    login(@superadmin)
    category_id = create_core_category!
    post emission_factors_path, params: { emission_factor: {
      identifier: "ef_html", name: "n", source: "s", value_per_unit: "1.0",
      unit_title: "kg", description: "", carbon_category_id: category_id } }
    assert_redirected_to emission_factors_path
  end

  test "update via turbo_stream replaces the row and toasts" do
    login(@superadmin)
    factor = create_core_emission_factor!(identifier: "ef_upd", value: 1.0)
    patch emission_factor_path(factor.id), as: :turbo_stream,
      params: { emission_factor: { name: "ใหม่", value_per_unit: "9.0", unit_title: "kg", source: "s" } }
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(factor)}"}, response.body
  end

  test "destroy via turbo_stream removes the row and toasts" do
    login(@superadmin)
    factor = create_core_emission_factor!(identifier: "ef_del", value: 1.0)
    delete emission_factor_path(factor.id), as: :turbo_stream
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="remove" target="#{ActionView::RecordIdentifier.dom_id(factor)}"}, response.body
  end
end
