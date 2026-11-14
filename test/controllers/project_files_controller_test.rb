require "test_helper"

class ProjectFilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @project = projects(:lisbon)
  end

  test "adds files to a project" do
    assert_difference -> { @project.files.count }, 2 do
      post project_files_url(@project), params: { project: { files: [
        fixture_file_upload("test.txt", "application/pdf"),
        fixture_file_upload("profile_image.png", "image/png")
      ] } }
    end

    assert_redirected_to project_url(@project, anchor: "files")
    assert_equal "2 files added", flash[:notice]
  end

  test "the project's page lists pictures and documents" do
    @project.files.attach(fixture_file_upload("test.txt", "application/pdf"))
    @project.files.attach(fixture_file_upload("profile_image.png", "image/png"))

    get project_url(@project)

    assert_response :success
    assert_select "#files li", count: 2
    assert_select "#files a", text: "test.txt"
    assert_select "#files img[alt='profile_image.png']"
  end

  test "refuses a file type it doesn't keep" do
    assert_no_difference -> { @project.files.count } do
      post project_files_url(@project), params: { project: { files: [ fixture_file_upload("test.txt", "application/x-msdownload") ] } }
    end

    assert_redirected_to project_url(@project, anchor: "files")
    assert_match "test.txt", flash[:alert]
  end

  test "says so when nothing was chosen" do
    post project_files_url(@project), params: { project: { files: [ "" ] } }

    assert_redirected_to project_url(@project, anchor: "files")
    assert_equal "Choose one or more files first.", flash[:alert]
  end

  test "deletes a file" do
    @project.files.attach(fixture_file_upload("test.txt", "application/pdf"))
    file = @project.files.first

    assert_difference -> { @project.files.count }, -1 do
      delete project_file_url(@project, file)
    end

    assert_redirected_to project_url(@project, anchor: "files")
  end

  test "can't add to or delete from another family's project" do
    theirs = families(:empty).projects.create!(name: "Theirs")
    theirs.files.attach(fixture_file_upload("test.txt", "application/pdf"))

    post project_files_url(theirs), params: { project: { files: [ fixture_file_upload("test.txt", "application/pdf") ] } }
    assert_response :not_found

    delete project_file_url(theirs, theirs.files.first)
    assert_response :not_found
    assert_equal 1, theirs.files.count
  end

  test "another family can't open a project's file" do
    @project.files.attach(fixture_file_upload("test.txt", "application/pdf"))
    path = rails_blob_path(@project.files.first, disposition: "inline")

    get path
    assert_response :redirect

    sign_in users(:empty)
    get path
    assert_response :not_found
  end
end
