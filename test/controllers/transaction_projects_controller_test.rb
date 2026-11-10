require "test_helper"

class TransactionProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @project = projects(:lisbon)
    @entry = entries(:transaction)
  end

  test "the transaction drawer has a project select" do
    get transaction_url(@entry)

    assert_response :success
    assert_select "##{dom_id(@entry, :project)} select[name='transaction_project[project_id]']" do
      assert_select "option[selected][value='#{@project.id}']"
    end
  end

  test "moves a transaction to another project" do
    other = @user.family.projects.create!(name: "Work")

    patch transaction_project_url(@entry), params: { transaction_project: { project_id: other.id } }, as: :turbo_stream

    assert_response :success
    assert_equal other, ProjectTransaction.project_for(@entry.transaction)
  end

  test "choosing no project takes it out" do
    patch transaction_project_url(@entry), params: { transaction_project: { project_id: "" } }

    assert_response :see_other
    assert_nil ProjectTransaction.project_for(@entry.transaction)
  end

  test "a read-only share can't change the project" do
    entry = Entry.create!(account: accounts(:credit_card), name: "Taxi", date: Date.current, currency: "USD", amount: 15, entryable: Transaction.new)
    sign_in users(:family_member)

    patch transaction_project_url(entry), params: { transaction_project: { project_id: @project.id } }

    assert_nil ProjectTransaction.project_for(entry.transaction)
  end
end
