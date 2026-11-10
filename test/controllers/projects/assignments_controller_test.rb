require "test_helper"

class Projects::AssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @project = projects(:lisbon)
  end

  test "new lists active projects" do
    get new_projects_assignment_url

    assert_response :success
    assert_select "option[value='#{@project.id}']"
    assert_select "option[value='#{projects(:old_kitchen).id}']", count: 0
  end

  test "adds the selected transactions to a project" do
    entry = Entry.create!(account: accounts(:depository), name: "Hotel", date: Date.current, currency: "USD", amount: 120, entryable: Transaction.new)

    post projects_assignment_url, params: { project_assignment: { project_id: @project.id, entry_ids: [ entry.id ] } }

    assert_response :see_other
    assert_equal @project, ProjectTransaction.project_for(entry.transaction)
    assert_equal "1 transaction added to Lisbon trip", flash[:notice]
  end

  test "no project takes them out" do
    post projects_assignment_url, params: { project_assignment: { project_id: "", entry_ids: [ entries(:transaction).id ] } }

    assert_nil ProjectTransaction.project_for(transactions(:one))
  end

  test "skips transactions in accounts the user can only read" do
    entry = Entry.create!(account: accounts(:credit_card), name: "Taxi", date: Date.current, currency: "USD", amount: 15, entryable: Transaction.new)
    sign_in users(:family_member)

    post projects_assignment_url, params: { project_assignment: { project_id: @project.id, entry_ids: [ entry.id ] } }

    assert_nil ProjectTransaction.project_for(entry.transaction)
  end
end
