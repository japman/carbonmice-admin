require "application_system_test_case"

class CarbonCreditsTest < ApplicationSystemTestCase
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

  test "filtering by user re-renders cc_list without reload and advances URL" do
    user1 = create_core_user!(email: "alice@example.com")
    user2 = create_core_user!(email: "bob@example.com")
    create_core_carbon_credit!(user_id: user1.id, amount: 100)
    create_core_carbon_credit!(user_id: user2.id, amount: 200)
    login_admin
    visit carbon_credits_path
    assert_selector "#cc_list", text: "alice@example.com"
    assert_selector "#cc_list", text: "bob@example.com"

    # Select alice via the filter
    within "form[data-controller='filter']" do
      select "alice@example.com", from: "user_id"
    end
    # The list re-renders showing only alice, URL advances
    within "#cc_list" do
      assert_text "alice@example.com"
      assert_no_text "bob@example.com"
    end
    assert_current_path(/user_id=/)
  end

  test "creating a credit shows the new row and a toast, and closes the modal" do
    user = create_core_user!(email: "newcredit@example.com")
    login_admin
    visit carbon_credits_path
    click_link "เพิ่ม carbon credit"
    assert_selector "turbo-frame#modal h2", text: "เพิ่ม carbon credit"
    within "turbo-frame#modal" do
      select "newcredit@example.com", from: "carbon_credit[user_id]"
      fill_in "carbon_credit[carbon_credit]", with: "150"
      click_on "เพิ่ม"
    end
    assert_selector "#toast_container", text: "เพิ่ม carbon credit แล้ว"
    assert_selector "#cc_rows", text: "newcredit@example.com"
    assert_no_selector "turbo-frame#modal div"
  end

  test "editing a credit updates the row and toasts" do
    user = create_core_user!(email: "editcredit@example.com")
    credit = create_core_carbon_credit!(user_id: user.id, amount: 100)
    login_admin
    visit carbon_credits_path
    within "##{dom_id(credit)}" do
      click_on "แก้ไข"
    end
    assert_selector "turbo-frame#modal h2", text: "แก้ไข carbon credit"
    within "turbo-frame#modal" do
      fill_in "carbon_credit[carbon_credit]", with: "300"
      click_on "บันทึก"
    end
    assert_selector "#toast_container", text: "บันทึกแล้ว"
    assert_selector "##{dom_id(credit)}", text: "300"
  end

  test "deleting a credit removes its row after the styled confirm" do
    user = create_core_user!(email: "delcredit@example.com")
    credit = create_core_carbon_credit!(user_id: user.id, amount: 50)
    login_admin
    visit carbon_credits_path
    assert_selector "##{dom_id(credit)}"
    within "##{dom_id(credit)}" do
      click_on "ลบ"
    end
    click_on "ยืนยัน"
    assert_no_selector "##{dom_id(credit)}"
    assert_selector "#toast_container", text: "ลบ carbon credit แล้ว"
  end

  test "server-rejected create keeps modal open with error" do
    user = create_core_user!(email: "rejectcredit@example.com")
    login_admin
    visit carbon_credits_path
    click_link "เพิ่ม carbon credit"
    assert_selector "turbo-frame#modal h2", text: "เพิ่ม carbon credit"
    within "turbo-frame#modal" do
      select "rejectcredit@example.com", from: "carbon_credit[user_id]"
      # amount 0 is rejected server-side (domain validates > 0)
      fill_in "carbon_credit[carbon_credit]", with: "0"
      click_on "เพิ่ม"
    end
    assert_selector "turbo-frame#modal .text-danger"
  end
end
