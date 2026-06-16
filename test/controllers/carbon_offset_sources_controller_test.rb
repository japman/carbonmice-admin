require "test_helper"

class CarbonOffsetSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "index lists sources and shows warning banner" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Biomass Energy", name_th: "ชีวมวล")
    get carbon_offset_sources_path
    assert_response :success
    assert_match "Biomass Energy", response.body
    assert_match "🔒", response.body
    assert_match "ระบบหลัก", response.body   # warning banner
  end

  test "creates a source with audit entry" do
    login(@superadmin)
    assert_difference -> { AuditLog.where(action: "master_data.offset_source_created").count } => 1 do
      post carbon_offset_sources_path, params: { carbon_offset_source: {
        name: "Solar Energy New", name_th: "พลังงานแสงอาทิตย์" } }
    end
    assert_redirected_to carbon_offset_sources_path
    assert Core::CarbonOffsetSource.kept.find_by(name: "Solar Energy New").present?
  end

  test "create error with duplicate name re-renders new 422 preserving input" do
    login(@superadmin)
    create_core_offset_source!(name: "Dup Source")
    assert_no_difference -> { Core::CarbonOffsetSource.kept.count } do
      post carbon_offset_sources_path, params: { carbon_offset_source: {
        name: "Dup Source", name_th: "ซ้ำ" } }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='carbon_offset_source[name]'][value='Dup Source']"
  end

  test "update re-renders edit 422 when name_th too long" do
    login(@superadmin)
    src = create_core_offset_source!(name: "Solar Energy")
    patch carbon_offset_source_path(src.id), params: { carbon_offset_source: { name_th: "ก" * 256 } }
    assert_response :unprocessable_entity
    assert_select "input[name='carbon_offset_source[name_th]'][value=?]", "ก" * 256
  end

  test "edit renders form with locked name field" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Wind Energy", name_th: nil)
    get edit_carbon_offset_source_path(source.id)
    assert_response :success
    assert_select "input[name='carbon_offset_source[name]'][disabled]"
  end

  test "update edits name_th with audit entry and name param is ignored" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Wind Energy", name_th: "พลังงานลม")
    assert_difference -> { AuditLog.where(action: "master_data.offset_source_renamed").count } => 1 do
      patch carbon_offset_source_path(source.id),
            params: { carbon_offset_source: { name_th: "ลม", name: "HACKED" } }
    end
    assert_redirected_to carbon_offset_sources_path
    source.reload
    assert_equal "ลม", source.name_th
    assert_equal "Wind Energy", source.name   # strong params drop :name
  end

  test "destroy soft-deletes when no pricing tiers and creates audit entry" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Hydro Energy")
    assert_difference -> { AuditLog.where(action: "master_data.offset_source_deleted").count } => 1 do
      delete carbon_offset_source_path(source.id)
    end
    assert_redirected_to carbon_offset_sources_path
    assert source.reload.deleted_at.present?
  end

  test "destroy is blocked when a pricing tier references the source" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Geothermal")
    create_core_offset_tier!(source_id: source.id, min: 0, max: 100, price: 50)
    assert_no_difference -> { AuditLog.where(action: "master_data.offset_source_deleted").count } do
      delete carbon_offset_source_path(source.id)
    end
    assert_redirected_to carbon_offset_sources_path
    assert_nil source.reload.deleted_at
  end

  test "viewer redirected to root_path and cannot write" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    source = create_core_offset_source!(name: "Viewer Source")

    # viewer can read index
    get carbon_offset_sources_path
    assert_response :success

    # viewer cannot create
    post carbon_offset_sources_path, params: { carbon_offset_source: { name: "New", name_th: nil } }
    assert_redirected_to root_path

    # viewer cannot update
    patch carbon_offset_source_path(source.id), params: { carbon_offset_source: { name_th: "x" } }
    assert_redirected_to root_path

    # viewer cannot delete
    delete carbon_offset_source_path(source.id)
    assert_redirected_to root_path

    # source unchanged
    assert_nil source.reload.deleted_at
  end

  # ---------------------------------------------------------------------------
  # Turbo Stream tests
  # ---------------------------------------------------------------------------

  test "create via turbo_stream prepends a row, closes the modal, and toasts" do
    login(@superadmin)
    assert_difference -> { Core::CarbonOffsetSource.kept.count } => 1 do
      post carbon_offset_sources_path, as: :turbo_stream, params: { carbon_offset_source: {
        name: "Stream Source", name_th: "แหล่งสตรีม" } }
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="prepend" target="cos_rows"}, response.body
    assert_match %r{turbo-stream action="update" target="modal"}, response.body
    assert_match %r{turbo-stream action="append" target="toast_container"}, response.body
    assert_match "สร้างแหล่งออฟเซ็ตแล้ว", response.body
  end

  test "create via HTML still redirects (no-JS fallback)" do
    login(@superadmin)
    post carbon_offset_sources_path, params: { carbon_offset_source: {
      name: "HTML Source", name_th: nil } }
    assert_redirected_to carbon_offset_sources_path
  end

  test "update via turbo_stream replaces the row and toasts" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Update Source", name_th: "ก่อน")
    patch carbon_offset_source_path(source.id), as: :turbo_stream,
      params: { carbon_offset_source: { name_th: "หลัง" } }
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(source)}"}, response.body
    assert_match "บันทึกแล้ว", response.body
  end

  test "destroy via turbo_stream removes the row and toasts" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Delete Source")
    delete carbon_offset_source_path(source.id), as: :turbo_stream
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="remove" target="#{ActionView::RecordIdentifier.dom_id(source)}"}, response.body
    assert_match "ลบแหล่งออฟเซ็ตแล้ว", response.body
  end
end
