require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @project = projects(:lisbon)
  end

  test "needs a name and a known kind" do
    project = @family.projects.new(kind: "holiday")

    assert_not project.valid?
    assert project.errors.added?(:name, :blank)
    assert project.errors.of_kind?(:kind, :inclusion)
  end

  test "can't end before it starts" do
    @project.end_on = @project.start_on - 1

    assert_not @project.valid?
    assert @project.errors.added?(:end_on, :before_start)
  end

  test "a budget must be positive" do
    @project.budget = 0

    assert_not @project.valid?
    assert @project.errors.of_kind?(:budget, :greater_than)
  end

  test "defaults to the family currency" do
    project = @family.projects.create!(name: "Garden")

    assert_equal @family.primary_currency_code, project.currency
    assert_equal "project", project.kind
    assert_equal "briefcase", project.icon
  end

  test "a trip gets the plane icon" do
    assert_equal "plane", @project.icon
  end

  test "archives and restores" do
    @project.archive!
    assert @project.archived?
    assert_not_includes @family.projects.active, @project

    @project.unarchive!
    assert_includes @family.projects.active, @project
  end

  test "assigning moves a transaction from its old project" do
    other = @family.projects.create!(name: "Work")
    transaction = transactions(:one)

    assert_equal 1, other.assign_transactions!([ transaction.id ])

    assert_equal other, ProjectTransaction.project_for(transaction)
    assert_empty @project.reload.transactions
  end

  test "assigning ignores another family's transactions" do
    stranger = families(:empty).accounts.create!(name: "Theirs", balance: 0, currency: "USD", accountable: Depository.new)
    entry = create_transaction(account: stranger)

    assert_equal 0, @project.assign_transactions!([ entry.entryable_id ])
    assert_nil ProjectTransaction.project_for(entry.transaction)
  end

  test "unassigning only touches this project's links" do
    other = @family.projects.create!(name: "Work")

    assert_equal 0, other.unassign_transactions!([ transactions(:one).id ])
    assert_equal 1, @project.unassign_transactions!([ transactions(:one).id ])
  end

  test "deleting keeps the transactions and IOUs" do
    iou = ious(:client_fee)
    iou.update!(project: @project)

    assert_no_difference -> { Transaction.count } do
      @project.destroy!
    end

    assert_nil iou.reload.project_id
    assert_nil ProjectTransaction.project_for(transactions(:one))
  end

  test "an IOU can't join another family's project" do
    project = families(:empty).projects.create!(name: "Theirs")
    iou = ious(:client_fee)
    iou.project = project

    assert_not iou.valid?
    assert iou.errors.include?(:project)
  end
end
