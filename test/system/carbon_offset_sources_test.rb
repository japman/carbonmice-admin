require "application_system_test_case"

class CarbonOffsetSourcesTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_admin
    AdminUser.create!(email_address: "ad@pea.co.th", password: "password-for-tests",
                      name: "แอด", role: :admin)
    visit new_session_path
    fill_in "email_address", with: "ad@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  test "creating a source shows the new row and a toast, and closes the modal" do
    login_admin
    visit carbon_offset_sources_path
    click_link "เพิ่มแหล่ง"
    assert_selector "turbo-frame#modal h2", text: "เพิ่มแหล่งออฟเซ็ต"
    fill_in "carbon_offset_source[name]", with: "New Source"
    fill_in "carbon_offset_source[name_th]", with: "แหล่งใหม่"
    within "turbo-frame#modal" do
      click_on "เพิ่มแหล่ง"
    end
    assert_selector "#toast_container", text: "สร้างแหล่งออฟเซ็ตแล้ว"
    assert_selector "#cos_rows", text: "แหล่งใหม่"
    assert_no_selector "turbo-frame#modal div"
  end

  test "editing Thai name updates the row and toasts" do
    source = create_core_offset_source!(name: "Edit Source", name_th: "ชื่อเดิม")
    login_admin
    visit carbon_offset_sources_path
    assert_selector "#cos_rows", text: "ชื่อเดิม"
    within "##{dom_id(source)}" do
      click_on "แก้ชื่อไทย"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ชื่อไทย: Edit Source"
    fill_in "carbon_offset_source[name_th]", with: "ชื่อใหม่"
    click_on "บันทึก"
    assert_selector "#toast_container", text: "บันทึกแล้ว"
    assert_selector "#cos_rows", text: "ชื่อใหม่"
    assert_no_selector "#cos_rows", text: "ชื่อเดิม"
  end

  test "deleting a source removes its row after the styled confirm" do
    source = create_core_offset_source!(name: "Delete Source", name_th: "ลบได้")
    login_admin
    visit carbon_offset_sources_path
    assert_selector "#cos_rows", text: "ลบได้"
    within "##{dom_id(source)}" do
      click_on "ลบ"
    end
    click_on "ยืนยัน"
    assert_no_selector "#cos_rows", text: "ลบได้"
    assert_selector "#toast_container", text: "ลบแหล่งออฟเซ็ตแล้ว"
  end

  test "server-rejected create (duplicate name) keeps modal open with error" do
    create_core_offset_source!(name: "Existing Source")
    login_admin
    visit carbon_offset_sources_path
    click_link "เพิ่มแหล่ง"
    assert_selector "turbo-frame#modal h2", text: "เพิ่มแหล่งออฟเซ็ต"
    # Fill with a name that passes HTML5 validation but the server rejects (duplicate)
    fill_in "carbon_offset_source[name]", with: "Existing Source"
    fill_in "carbon_offset_source[name_th]", with: ""
    within "turbo-frame#modal" do
      click_on "เพิ่มแหล่ง"
    end
    assert_selector "turbo-frame#modal .text-danger"
  end
end
