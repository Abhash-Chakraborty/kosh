require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @project = projects(:lisbon)
  end

  test "lists active projects with what they cost" do
    get projects_url

    assert_response :success
    assert_select "##{dom_id(@project)}", text: /Lisbon trip/
    assert_select "##{dom_id(@project)}", text: /\$10\.00/
    assert_select "##{dom_id(projects(:old_kitchen))}", count: 0
    assert_select "a[href='#{projects_path(archived: 1)}']"
  end

  test "the archived toggle shows archived projects" do
    get projects_url(archived: 1)

    assert_response :success
    assert_select "##{dom_id(projects(:old_kitchen))}"
    assert_select "##{dom_id(@project)}", count: 0
  end

  test "shows the empty state without projects" do
    @family.projects.destroy_all

    get projects_url

    assert_response :success
    assert_select "a[href='#{new_project_path}']"
  end

  test "shows a project with its totals, transactions and IOUs" do
    ious(:dinner).update!(project: @project)

    get project_url(@project)

    assert_response :success
    assert_select "h1", text: "Lisbon trip"
    assert_select "a[href='#{transaction_path(entries(:transaction))}']"
    assert_select "##{dom_id(ious(:dinner))}"
    assert_select "a[href='#{new_iou_path(project_id: @project.id, from_project: 1)}']"
    assert_select "[role=progressbar]"
  end

  test "shows the cost sheet with open IOUs and the final cost" do
    ious(:dinner).update!(project: projects(:lisbon), category: categories(:food_and_drink))

    get project_url(projects(:lisbon))

    assert_response :success
    assert_select "h2", text: "Cost sheet"
    assert_select "[data-cost-group] p", text: "To pay Maya"
    assert_select "dt", text: "Still to pay"
    assert_select "dt", text: "Final cost to you"
    assert_select "dt", text: "Left to pay from your pocket"
  end

  test "a project that brings money in shows its profit" do
    ious(:client_fee).update!(project: projects(:lisbon))

    get project_url(projects(:lisbon))

    assert_select "dt", text: "Coming in, in all"
    assert_select "dt", text: "Profit after every cost"
    assert_select "dt", text: "Final cost to you", count: 0
  end

  test "the project page and Home switch between the overview and each project" do
    get project_url(projects(:lisbon))
    assert_select "nav a[href='#{root_path}']", text: "Overview"
    assert_select "nav a[aria-current='true'][href='#{project_path(projects(:lisbon))}']", text: "Lisbon trip"

    get root_url
    assert_select "nav a[aria-current='true'][href='#{root_path}']", text: "Overview"
    assert_select "nav a[href='#{project_path(projects(:lisbon))}']", text: "Lisbon trip"
    assert_select "nav a[href='#{project_path(projects(:old_kitchen))}']", count: 0
  end

  test "the projects page says where each project stands" do
    ious(:dinner).update!(project: projects(:lisbon))

    get projects_url

    assert_select "##{dom_id(projects(:lisbon))} p", text: "$40.00 left to pay · $50.00 in all"
  end

  test "the account filter narrows the project page" do
    get project_url(@project, account_id: accounts(:connected).id)

    assert_response :success
    assert_select "a[href='#{transaction_path(entries(:transaction))}']", count: 0
  end

  test "a member doesn't see transactions in accounts not shared with them" do
    entry = create_connected_entry
    sign_in users(:family_member)

    get project_url(@project)

    assert_response :success
    assert_select "a[href='#{transaction_path(entry)}']", count: 0
    assert_select "a[href='#{transaction_path(entries(:transaction))}']"
  end

  test "creates a project" do
    assert_difference -> { @family.projects.count }, 1 do
      post projects_url, params: { project: { name: "Garden", kind: "project", budget: "300", color: "#e99537" } }
    end

    project = @family.projects.order(:created_at).last
    assert_redirected_to project_path(project)
    assert_equal 300, project.budget
    assert_equal "USD", project.currency
  end

  test "a project without a name isn't saved" do
    assert_no_difference -> { @family.projects.count } do
      post projects_url, params: { project: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "updates a project" do
    patch project_url(@project), params: { project: { name: "Porto trip" } }

    assert_redirected_to project_path(@project)
    assert_equal "Porto trip", @project.reload.name
  end

  test "archives and restores a project" do
    patch archive_project_url(@project)
    assert @project.reload.archived?

    patch unarchive_project_url(@project)
    assert_not @project.reload.archived?
  end

  test "deleting a project keeps its transactions" do
    assert_no_difference -> { Transaction.count } do
      delete project_url(@project)
    end

    assert_redirected_to projects_path
    assert_not Project.exists?(@project.id)
  end

  test "can't open another family's project" do
    project = families(:empty).projects.create!(name: "Theirs")

    get project_url(project)

    assert_response :not_found
  end

  private
    def create_connected_entry
      Entry.create!(account: accounts(:connected), name: "Hidden", date: Date.current, currency: "USD", amount: 20, entryable: Transaction.new).tap do |entry|
        @project.assign_transactions!([ entry.entryable_id ])
      end
    end
end
