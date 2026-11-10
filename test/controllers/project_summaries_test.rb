require "test_helper"

# The Projects section on Home and on Reports.
class ProjectSummariesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @project = projects(:lisbon)
  end

  test "Home shows active projects" do
    get root_path

    assert_response :success
    assert_select "section[data-section-key='projects'] a[href='#{project_path(@project)}']", text: /Lisbon trip/
    assert_select "section[data-section-key='projects'] a[href='#{project_path(projects(:old_kitchen))}']", count: 0
  end

  test "the Home section can be hidden and added back" do
    patch dashboard_section_hidden_path("projects"), params: { hidden: true }
    assert_includes @user.reload.dashboard_hidden_sections, "projects"

    get root_path(customize: true)
    assert_select "section[data-section-key='projects']", count: 0
    assert_select "form[action='#{dashboard_section_hidden_path("projects")}']"
  end

  test "Home offers a first project when there are none" do
    @user.family.projects.destroy_all

    get root_path

    assert_select "section[data-section-key='projects'] a[href='#{new_project_path}']"
  end

  test "Reports shows active projects" do
    get reports_path

    assert_response :success
    assert_select "[data-section-key='projects'] a[href='#{project_path(@project)}']"
  end
end
