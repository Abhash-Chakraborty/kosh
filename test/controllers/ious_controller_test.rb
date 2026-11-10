require "test_helper"

class IousControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @iou = ious(:client_fee)
  end

  test "lists open IOUs by person with the two totals" do
    get ious_url

    assert_response :success
    assert_select "#" + dom_id(@iou)
    assert_select "#" + dom_id(ious(:dinner))
    assert_select "p", text: "People owe you"
    assert_select "p", text: "You owe"
    assert_select "p", text: "$1,500.00"
  end

  test "an overdue IOU says so" do
    @iou.update!(due_on: Date.current - 3)

    get ious_url

    assert_select "##{dom_id(@iou)} .text-destructive", text: /Overdue since/
  end

  test "settled IOUs move to their own section with their payments" do
    payment = ious(:dinner).record_payment(amount: 40, date: Date.current, account: accounts(:depository))

    get ious_url

    assert_select "details summary", text: /Settled/
    assert_select "details ##{dom_id(payment)}"
  end

  test "shows the empty state when nothing is owed" do
    @family.ious.destroy_all

    get ious_url

    assert_response :success
    assert_select "p", text: "Nothing is owed either way."
    assert_select "a[href='#{new_iou_path}']"
  end

  test "new opens the form" do
    get new_iou_url

    assert_response :success
    assert_select "form[action='#{ious_path}']"
  end

  test "creates an IOU" do
    assert_difference -> { @family.ious.count }, 1 do
      post ious_url, params: { iou: {
        direction: "owed_to_me", person: "Ana", description: "Logo work", amount: "250",
        currency: "USD", due_on: Date.current + 7, account_id: accounts(:depository).id
      } }
    end

    iou = @family.ious.order(:created_at).last
    assert_redirected_to ious_url
    assert_equal "Ana", iou.person
    assert_equal accounts(:depository), iou.account
  end

  test "a missing description renders the form again" do
    assert_no_difference -> { Iou.count } do
      post ious_url, params: { iou: { direction: "i_owe", person: "Ana", description: "", amount: "10" } }
    end

    assert_response :unprocessable_entity
  end

  test "updates an IOU" do
    patch iou_url(@iou), params: { iou: { amount: "1800", notes: "Two pages more" } }

    assert_redirected_to ious_url
    assert_equal 1800, @iou.reload.amount
    assert_equal "Two pages more", @iou.notes
  end

  test "deletes an IOU" do
    assert_difference -> { Iou.count }, -1 do
      delete iou_url(@iou)
    end

    assert_redirected_to ious_url
  end

  test "records a payment as a transaction and undoes it" do
    get new_iou_payment_url(@iou)
    assert_response :success

    assert_difference -> { accounts(:depository).entries.count }, 1 do
      post iou_payments_url(@iou), params: { iou_payment: { amount: "600", date: Date.current, account_id: accounts(:depository).id } }
    end

    assert_redirected_to ious_url
    payment = @iou.payments.reload.last
    assert_equal(-600, payment.entry.amount)

    assert_difference -> { accounts(:depository).entries.count }, -1 do
      delete iou_payment_url(@iou, payment)
    end

    assert_redirected_to ious_url
    assert_equal 1500, @iou.reload.remaining_amount
  end

  test "a payment above what's left renders the dialog again" do
    assert_no_difference -> { Entry.count } do
      post iou_payments_url(@iou), params: { iou_payment: { amount: "2000", date: Date.current, account_id: accounts(:depository).id } }
    end

    assert_response :unprocessable_entity
  end

  test "guests can look but not change anything" do
    sign_in family_guest

    get ious_url
    assert_response :success

    assert_no_difference -> { Iou.count } do
      post ious_url, params: { iou: { direction: "i_owe", person: "Ana", description: "Lunch", amount: "10" } }
    end
  end

  test "another family's IOU is not found" do
    other = families(:empty).ious.create!(direction: "i_owe", person: "X", description: "Y", amount: 5)

    get edit_iou_url(other)

    assert_response :not_found
  end

  test "a member who can't see the account doesn't see its name" do
    ious(:client_fee).record_payment(amount: 100, date: Date.current, account: accounts(:depository))
    account_shares(:depository_shared_with_member).destroy!
    sign_in users(:family_member)

    get ious_url

    assert_response :success
    assert_select "##{dom_id(@iou)}", text: /Owed to you/
    assert_select "##{dom_id(@iou)}", text: /Checking Account/, count: 0
  end

  test "new from a project picks that project" do
    project = projects(:lisbon)

    get new_iou_url(project_id: project.id, from_project: 1)

    assert_response :success
    assert_select "input[type=hidden][name='iou[project_id]'][value='#{project.id}']"
    assert_select "input[type=hidden][name=from_project]"
  end

  test "an IOU added from a project goes back to it" do
    project = projects(:lisbon)

    post ious_url, params: { from_project: "1", iou: {
      direction: "i_owe", person: "Ana", description: "Hotel share", amount: "80", currency: "USD", project_id: project.id
    } }

    assert_redirected_to project_path(project)
    assert_equal project, @family.ious.find_by(description: "Hotel share").project
  end

  test "an IOU row links to its project" do
    @iou.update!(project: projects(:lisbon))

    get ious_url

    assert_select "##{dom_id(@iou)} a[href='#{project_path(projects(:lisbon))}']", text: "Lisbon trip"
  end
end
