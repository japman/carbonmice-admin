require "application_system_test_case"

class CategoriesTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_admin
    AdminUser.create!(email_address: "cat_ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "cat_ad@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "editing a category name updates the row in place and shows a toast" do
    ef = create_core_emission_factor!(identifier: "cat_sys_ef1")
    category = Core::CarbonCategory.find(ef.carbon_category_id)
    login_admin
    visit categories_path
    assert_selector "##{dom_id(category)}", text: "หมวดทดสอบ"
    within "##{dom_id(category)}" do
      click_on "แก้ชื่อไทย"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ชื่อหมวด: #{category.name_eng}"
    within "turbo-frame#modal" do
      fill_in "category[name_thai]", with: "ชื่อใหม่จากระบบ"
      click_on "บันทึก"
    end
    assert_selector "#toast_container", text: "บันทึกชื่อหมวดแล้ว"
    assert_selector "##{dom_id(category)}", text: "ชื่อใหม่จากระบบ"
    assert_no_selector "turbo-frame#modal div"
  end

  test "server-rejected submit (blank name) keeps modal open with error" do
    ef = create_core_emission_factor!(identifier: "cat_sys_ef2")
    category = Core::CarbonCategory.find(ef.carbon_category_id)
    login_admin
    visit categories_path
    within "##{dom_id(category)}" do
      click_on "แก้ชื่อไทย"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ชื่อหมวด: #{category.name_eng}"
    # Use JS to clear the field (bypassing HTML5 required constraint so the request reaches the server)
    within "turbo-frame#modal" do
      field = find("input[name='category[name_thai]']")
      field.native.clear
      # Force remove the required attribute so the browser submits blank
      page.execute_script("arguments[0].removeAttribute('required')", field.native)
      click_on "บันทึก"
    end
    assert_selector "turbo-frame#modal .text-danger"
  end
end
