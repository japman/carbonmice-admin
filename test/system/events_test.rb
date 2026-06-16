require "application_system_test_case"

class EventsTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def login_admin
    AdminUser.create!(email_address: "sa@pea.co.th", password: "password-for-tests",
                      name: "ซุป", role: :superadmin)
    visit new_session_path
    fill_in "email_address", with: "sa@pea.co.th"
    fill_in "password", with: "password-for-tests"
    click_on "เข้าสู่ระบบ"
    assert_text "ภาพรวมระบบ"
  end

  def seed_statuses
    create_core_event_status!(name_eng: "draft", name_thai: "บันทึกร่าง", running_order: 1)
    create_core_event_status!(name_eng: "collecting", name_thai: "กำลังรับสมัคร", running_order: 2)
    create_core_event_status!(name_eng: "in_progress", name_thai: "กำลังดำเนินการ", running_order: 3)
  end

  test "typing in search live-filters ev_list and advances URL" do
    seed_statuses
    create_core_event!(name_thai: "งานหนังสือ", status: "draft")
    create_core_event!(name_thai: "งานวิ่ง", status: "collecting")
    login_admin
    visit events_path

    assert_selector "#ev_list", text: "งานหนังสือ"
    assert_selector "#ev_list", text: "งานวิ่ง"

    fill_in "search", with: "หนังสือ"
    within "#ev_list" do
      assert_text "งานหนังสือ"
      assert_no_text "งานวิ่ง"
    end
    assert_current_path(/search=/)
  end

  test "choosing a status filter re-renders ev_list and advances URL" do
    seed_statuses
    create_core_event!(name_thai: "งานหนังสือ", status: "draft")
    create_core_event!(name_thai: "งานวิ่ง", status: "collecting")
    login_admin
    visit events_path

    within "form[data-controller='filter']" do
      select "กำลังรับสมัคร (collecting)", from: "status"
    end

    within "#ev_list" do
      assert_text "งานวิ่ง"
      assert_no_text "งานหนังสือ"
    end
    assert_current_path(/status=collecting/)
  end

  test "แก้ไขรายละเอียด opens modal, saving updates event_details in place with toast" do
    seed_statuses
    event = create_core_event!(name_thai: "ชื่อเดิม", name_eng: "Old Name")
    login_admin
    visit event_path(event.id)

    assert_selector "#event_details"
    click_on "แก้ไขรายละเอียด"
    assert_selector "turbo-frame#modal h2", text: "แก้ไขอีเว้นท์"

    within "turbo-frame#modal" do
      fill_in "event[name_thai]", with: "ชื่อใหม่"
      click_on "บันทึก"
    end

    assert_selector "#toast_container", text: "บันทึกการแก้ไขแล้ว"
    assert_selector "#event_details", text: "ชื่อใหม่"
    assert_no_selector "turbo-frame#modal div"
  end

  test "invalid edit keeps modal open with text-danger error" do
    seed_statuses
    event = create_core_event!(name_thai: "ชื่อ", name_eng: "Name")
    login_admin
    visit event_path(event.id)

    click_on "แก้ไขรายละเอียด"
    assert_selector "turbo-frame#modal h2", text: "แก้ไขอีเว้นท์"

    # A name longer than 255 chars triggers ValueTooLong -> ValidationFailed ->
    # UpdateDetails returns failure -> controller renders :edit 422 -> modal stays open.
    # Use JS to bypass the HTML maxlength attribute.
    within "turbo-frame#modal" do
      page.execute_script(
        "document.querySelector('input[name=\"event[name_thai]\"]').removeAttribute('maxlength')"
      )
      fill_in "event[name_thai]", with: "ก" * 300
      click_on "บันทึก"
    end

    assert_selector "turbo-frame#modal .text-danger"
  end
end
