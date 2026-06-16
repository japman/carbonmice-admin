require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  test "lists events with search and status filter" do
    login(@superadmin)
    create_core_event!(name_thai: "งานหนังสือ", status: "collecting")
    create_core_event!(name_thai: "งานวิ่ง", status: "draft")

    get events_path
    assert_response :success
    assert_select "td", text: "งานหนังสือ"

    get events_path, params: { search: "หนังสือ" }
    assert_select "td", text: "งานหนังสือ"
    assert_select "td", text: "งานวิ่ง", count: 0

    get events_path, params: { status: "draft" }
    assert_select "td", text: "งานวิ่ง"
    assert_select "td", text: "งานหนังสือ", count: 0
  end

  test "viewer can read the list and detail but sees no edit controls" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    event = create_core_event!(name_thai: "งานอ่านได้")
    get events_path
    assert_response :success
    get event_path(event.id)
    assert_response :success
    assert_select "form[action=?]", status_event_path(event.id), count: 0
    assert_select "a[href=?]", edit_event_path(event.id), count: 0
  end

  test "detail shows emissions per category" do
    login(@superadmin)
    event = create_core_event!(name_thai: "งานคาร์บอน")
    create_core_emission!(event_id: event.id, category_thai: "การเดินทาง", pre: 12.5)
    get event_path(event.id)
    assert_response :success
    assert_select "td", text: "การเดินทาง"
  end

  test "unknown event id redirects with alert" do
    login(@superadmin)
    get event_path("not-a-uuid")
    assert_redirected_to events_path
  end

  test "superadmin edits safe fields with an audit diff" do
    login(@superadmin)
    event = create_core_event!(name_thai: "เดิม")
    get edit_event_path(event.id)
    assert_response :success

    assert_difference -> { AuditLog.where(action: "events.updated").count } => 1 do
      patch event_path(event.id), params: { event: { name_thai: "ใหม่", province: "ขอนแก่น" } }
    end
    assert_redirected_to event_path(event.id)
    assert_equal "ใหม่", event.reload.name_thai
    log = AuditLog.where(action: "events.updated").order(:id).last
    assert_equal "ใหม่", log.change_set.dig("name_thai", "to")
  end

  test "update as turbo_stream replaces event_details and appends toast" do
    login(@superadmin)
    event = create_core_event!(name_thai: "ก่อน")
    patch event_path(event.id),
          params: { event: { name_thai: "หลัง" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{<turbo-stream[^>]+action="replace"[^>]+target="event_details"}, response.body
    assert_match %r{<turbo-stream[^>]+action="append"[^>]+target="toast_container"}, response.body
    assert_match "บันทึกการแก้ไขแล้ว", response.body
  end

  test "update error renders edit 422 with flash.now alert" do
    login(@superadmin)
    event = create_core_event!(name_thai: "ของเดิม")
    # Sending only non-whitelisted fields: update_params.permit filters them out,
    # resulting in empty attrs -> UpdateDetails fails "ไม่มีข้อมูลให้แก้ไข" -> 422
    patch event_path(event.id), params: { event: { event_status: "hacked" } }
    assert_response :unprocessable_entity
    assert_match "ไม่มีข้อมูลให้แก้ไข", response.body
  end

  test "status change follows the transition table and audits" do
    login(@superadmin)
    event = create_core_event!(status: "collecting")
    assert_difference -> { AuditLog.where(action: "events.status_changed").count } => 1 do
      patch status_event_path(event.id), params: { to: "in_progress" }
    end
    assert_equal "in_progress", event.reload.event_status

    assert_no_difference -> { AuditLog.where(action: "events.status_changed").count } do
      patch status_event_path(event.id), params: { to: "draft" }   # not allowed from in_progress
    end
    assert_equal "in_progress", event.reload.event_status
  end

  test "show renders danger zone with Thai status labels from DB" do
    login(@superadmin)
    create_core_event_status!(name_eng: "draft", name_thai: "บันทึกร่าง", running_order: 1)
    create_core_event_status!(name_eng: "in_progress", name_thai: "กำลังดำเนินการ", running_order: 5)
    event = create_core_event!(name_thai: "งานทดสอบสถานะ")

    get event_path(event.id)
    assert_response :success
    assert_match "บันทึกร่าง", response.body
    assert_match "กำลังดำเนินการ", response.body
    assert_match "border-danger", response.body
  end

  test "server-side transition guard rejects invalid status from full catalog dropdown" do
    login(@superadmin)
    create_core_event_status!(name_eng: "draft", name_thai: "บันทึกร่าง", running_order: 1)
    create_core_event_status!(name_eng: "collecting", name_thai: "กำลังรับสมัคร", running_order: 2)
    event = create_core_event!(status: "collecting")

    patch status_event_path(event.id), params: { to: "draft" }
    assert_redirected_to event_path(event.id)
    assert_equal "collecting", event.reload.event_status
  end

  test "status change captures request IP in audit log" do
    login(@superadmin)
    event = create_core_event!(status: "collecting")
    patch status_event_path(event.id), params: { to: "in_progress" }
    assert_equal "127.0.0.1", AuditLog.where(action: "events.status_changed").last.ip_address
  end

  test "viewer cannot change status or edit" do
    viewer = AdminUser.create!(email_address: "v2@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    event = create_core_event!(status: "collecting")
    patch status_event_path(event.id), params: { to: "in_progress" }
    assert_redirected_to root_path
    assert_equal "collecting", event.reload.event_status
    patch event_path(event.id), params: { event: { name_thai: "ห้าม" } }
    assert_redirected_to root_path
    assert_equal "งานทดสอบ", event.reload.name_thai
  end
end
