require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists categories and units read-only with locked name_eng" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_cat_seed")   # seeds a category + nothing else
    get categories_path
    assert_response :success
    assert_match "test_category", response.body
    assert_match "แก้ไขไม่ได้", response.body   # lock explanation
  end

  test "renames category Thai label with audit; name_eng untouchable — turbo_stream" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_cat_seed2")
    category = Core::CarbonCategory.find(f.carbon_category_id)
    assert_difference -> { AuditLog.where(action: "master_data.category_renamed").count } => 1 do
      patch category_path(category.id),
            params: { category: { name_thai: "ชื่อใหม่", name_eng: "hacked" } },
            as: :turbo_stream
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{replace[^>]*target="#{ActionView::RecordIdentifier.dom_id(category)}"}, response.body
    assert_match %r{append[^>]*target="toast_container"}, response.body
    assert_match "บันทึกชื่อหมวดแล้ว", response.body
    category.reload
    assert_equal "ชื่อใหม่", category.name_thai
    assert_equal "test_category", category.name_eng   # strong params drop name_eng
  end

  test "renames category Thai label — HTML format redirects" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_cat_seed_html")
    category = Core::CarbonCategory.find(f.carbon_category_id)
    patch category_path(category.id), params: { category: { name_thai: "ชื่อ HTML" } }
    assert_redirected_to categories_path
    assert_equal "ชื่อ HTML", category.reload.name_thai
  end

  test "blank name_thai renders edit with 422" do
    login(@superadmin)
    f = create_core_emission_factor!(identifier: "ef_cat_seed4")
    category = Core::CarbonCategory.find(f.carbon_category_id)
    patch category_path(category.id), params: { category: { name_thai: "" } }
    assert_response :unprocessable_entity
  end

  test "viewer cannot rename" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    f = create_core_emission_factor!(identifier: "ef_cat_seed3")
    category = Core::CarbonCategory.find(f.carbon_category_id)
    patch category_path(category.id), params: { category: { name_thai: "ห้าม" } }
    assert_redirected_to root_path
    assert_equal "หมวดทดสอบ", category.reload.name_thai
  end
end
