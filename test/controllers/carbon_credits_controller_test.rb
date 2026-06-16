require "test_helper"

class CarbonCreditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = AdminUser.create!(email_address: "sa@pea.co.th",
                                    password: "password-for-tests", name: "ซุป", role: :superadmin)
    @user = create_core_user!(email: "testuser@example.com")
  end

  def login(user)
    post session_path, params: { email_address: user.email_address, password: "password-for-tests" }
  end

  # ---------------------------------------------------------------------------
  # Index
  # ---------------------------------------------------------------------------

  test "index lists credits with user email and amount" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 500)
    get carbon_credits_path
    assert_response :success
    assert_match "testuser@example.com", response.body
    assert_match "500", response.body
  end

  test "index shows the updated_by stamp after a credit is updated" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 500)
    patch carbon_credit_path(credit.id), params: { carbon_credit: { carbon_credit: "750" } }
    get carbon_credits_path
    assert_response :success
    assert_match "carbonmice-admin:sa@pea.co.th", response.body   # updated_by column shows the stamp
  end

  test "index filters by user_id" do
    login(@superadmin)
    user2 = create_core_user!(email: "other@example.com")
    create_core_carbon_credit!(user_id: @user.id, amount: 100)
    create_core_carbon_credit!(user_id: user2.id, amount: 999)
    get carbon_credits_path, params: { user_id: @user.id }
    assert_response :success
    # The filtered user's credit appears in table rows
    assert_select "td", text: "testuser@example.com"
    # The other user's credit should not appear in table rows
    assert_select "td", text: "other@example.com", count: 0
  end

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  test "creates a carbon credit with audit entry" do
    login(@superadmin)
    assert_difference -> { AuditLog.where(action: "master_data.carbon_credit_created").count } => 1 do
      post carbon_credits_path, params: { carbon_credit: {
        user_id: @user.id, carbon_credit: "200", carbon_offset_source_id: "" } }
    end
    assert_redirected_to carbon_credits_path
    credit = Core::CarbonCredit.kept.find_by!(user_id: @user.id)
    assert_equal 200, credit.carbon_credit
  end

  test "creates a credit with a source" do
    login(@superadmin)
    source = create_core_offset_source!(name: "Solar")
    assert_difference -> { AuditLog.where(action: "master_data.carbon_credit_created").count } => 1 do
      post carbon_credits_path, params: { carbon_credit: {
        user_id: @user.id, carbon_credit: "50", carbon_offset_source_id: source.id } }
    end
    assert_redirected_to carbon_credits_path
    credit = Core::CarbonCredit.kept.order(created_at: :desc).first
    assert_equal source.id, credit.carbon_offset_source_id
  end

  test "create error with amount 0 re-renders new 422 preserving input" do
    login(@superadmin)
    assert_no_difference -> { Core::CarbonCredit.kept.count } do
      post carbon_credits_path, params: { carbon_credit: {
        user_id: @user.id, carbon_credit: "0", carbon_offset_source_id: "" } }
    end
    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # Update
  # ---------------------------------------------------------------------------

  test "update edits amount and creates audit entry" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 100)
    assert_difference -> { AuditLog.where(action: "master_data.carbon_credit_updated").count } => 1 do
      patch carbon_credit_path(credit.id), params: { carbon_credit: { carbon_credit: "300" } }
    end
    assert_redirected_to carbon_credits_path
    assert_equal 300, credit.reload.carbon_credit
  end

  test "submitting user_id on update does NOT change owner (strong params drops it)" do
    login(@superadmin)
    user2 = create_core_user!(email: "hacker@example.com")
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 100)
    patch carbon_credit_path(credit.id), params: { carbon_credit: { user_id: user2.id, carbon_credit: "200" } }
    # user_id is stripped by strong params before reaching the domain, so the update
    # succeeds with only the amount changed — verify the owner (user_id) is unchanged.
    assert_equal @user.id, credit.reload.user_id
  end

  test "update error re-renders edit 422" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 100)
    patch carbon_credit_path(credit.id), params: { carbon_credit: { carbon_credit: "-5" } }
    assert_response :unprocessable_entity
    assert_equal 100, credit.reload.carbon_credit
  end

  # ---------------------------------------------------------------------------
  # Destroy
  # ---------------------------------------------------------------------------

  test "destroy soft-deletes the credit and creates audit entry" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 100)
    assert_difference -> { AuditLog.where(action: "master_data.carbon_credit_deleted").count } => 1 do
      delete carbon_credit_path(credit.id)
    end
    assert_redirected_to carbon_credits_path
    assert credit.reload.deleted_at.present?
  end

  # ---------------------------------------------------------------------------
  # Viewer
  # ---------------------------------------------------------------------------

  test "viewer can read index but is redirected to root on writes" do
    viewer = AdminUser.create!(email_address: "v@pea.co.th",
                               password: "password-for-tests", name: "วิว", role: :viewer)
    login(viewer)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 50)

    # viewer can read index
    get carbon_credits_path
    assert_response :success

    # viewer cannot create
    post carbon_credits_path, params: { carbon_credit: { user_id: @user.id, carbon_credit: "10" } }
    assert_redirected_to root_path

    # viewer cannot update
    patch carbon_credit_path(credit.id), params: { carbon_credit: { carbon_credit: "999" } }
    assert_redirected_to root_path

    # viewer cannot delete
    delete carbon_credit_path(credit.id)
    assert_redirected_to root_path

    # credit unchanged
    assert_nil credit.reload.deleted_at
    assert_equal 50, credit.reload.carbon_credit
  end

  # ---------------------------------------------------------------------------
  # Turbo Stream tests
  # ---------------------------------------------------------------------------

  test "create via turbo_stream prepends a row, closes the modal, and toasts" do
    login(@superadmin)
    assert_difference -> { Core::CarbonCredit.kept.count } => 1 do
      post carbon_credits_path, as: :turbo_stream, params: { carbon_credit: {
        user_id: @user.id, carbon_credit: "100", carbon_offset_source_id: "" } }
    end
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="prepend" target="cc_rows"}, response.body
    assert_match %r{turbo-stream action="update" target="modal"}, response.body
    assert_match %r{turbo-stream action="append" target="toast_container"}, response.body
    assert_match "เพิ่ม carbon credit แล้ว", response.body
  end

  test "create via HTML still redirects (no-JS fallback)" do
    login(@superadmin)
    post carbon_credits_path, params: { carbon_credit: {
      user_id: @user.id, carbon_credit: "50", carbon_offset_source_id: "" } }
    assert_redirected_to carbon_credits_path
  end

  test "update via turbo_stream replaces the row and toasts" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 100)
    patch carbon_credit_path(credit.id), as: :turbo_stream,
      params: { carbon_credit: { carbon_credit: "250" } }
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(credit)}"}, response.body
    assert_match "บันทึกแล้ว", response.body
  end

  test "destroy via turbo_stream removes the row and toasts" do
    login(@superadmin)
    credit = create_core_carbon_credit!(user_id: @user.id, amount: 100)
    delete carbon_credit_path(credit.id), as: :turbo_stream
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match %r{turbo-stream action="remove" target="#{ActionView::RecordIdentifier.dom_id(credit)}"}, response.body
    assert_match "ลบ carbon credit แล้ว", response.body
  end
end
