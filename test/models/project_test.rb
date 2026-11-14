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

  test "has a known status and starts underway" do
    project = @family.projects.create!(name: "Shed")
    assert_equal "active", project.status
    assert project.underway?

    project.status = "paused"
    assert_not project.valid?
    assert project.errors.of_kind?(:status, :inclusion)
  end

  test "underway leaves out projects on hold, completed or archived" do
    on_hold = @family.projects.create!(name: "Shed", status: "on_hold")
    done = @family.projects.create!(name: "Fence", status: "completed")

    underway = @family.projects.underway

    assert_includes underway, @project
    assert_not_includes underway, on_hold
    assert_not_includes underway, done
    assert_not_includes underway, projects(:old_kitchen)
  end

  test "completing a project without an end date ends it today" do
    project = @family.projects.create!(name: "Shed", start_on: Date.current - 5)

    project.set_status!("completed")

    assert project.completed?
    assert_equal Date.current, project.end_on
  end

  test "completing keeps an end date that is already set, and resuming keeps it too" do
    ended = @project.end_on

    @project.set_status!("completed")
    assert_equal ended, @project.end_on

    @project.set_status!("active")
    assert @project.underway?
    assert_equal ended, @project.end_on
  end

  test "knows where a day falls in its dates" do
    project = @family.projects.new(name: "Trip", start_on: Date.new(2026, 11, 26), end_on: Date.new(2026, 12, 6))

    assert_equal :upcoming, project.phase(Date.new(2026, 11, 14))
    assert_equal :ongoing, project.phase(Date.new(2026, 11, 28))
    assert_equal :past, project.phase(Date.new(2026, 12, 7))
    assert_equal 3, project.day_number(Date.new(2026, 11, 28))
    assert_nil project.day_number(Date.new(2026, 12, 7))
    assert_equal 11, project.total_days
    assert_nil @family.projects.new(name: "Open").phase
  end

  test "refuses files that are too large or of a type it doesn't keep" do
    @project.files.attach(io: StringIO.new("x"), filename: "run.exe", content_type: "application/x-msdownload")

    assert_not @project.valid?
    assert @project.errors.of_kind?(:files, :wrong_type)
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
