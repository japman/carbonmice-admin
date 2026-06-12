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
end
