# frozen_string_literal: true

require "test_helper"

class Api::V1::ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @project = projects(:lisbon)

    @user.api_keys.active.destroy_all

    @api_key = ApiKey.create!(
      user: @user,
      name: "Test Read-Write Key",
      scopes: [ "read_write" ],
      source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )

    @read_only_api_key = ApiKey.create!(
      user: @user,
      name: "Test Read-Only Key",
      scopes: [ "read" ],
      display_key: "test_ro_#{SecureRandom.hex(8)}",
      source: "mobile"
    )

    Redis.new.del("api_rate_limit:#{@api_key.id}")
    Redis.new.del("api_rate_limit:#{@read_only_api_key.id}")
  end

  test "index needs authentication" do
    get api_v1_projects_url

    assert_response :unauthorized
  end

  test "index lists the family's projects with pagination" do
    get api_v1_projects_url, headers: api_headers(@read_only_api_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ @project.id, projects(:old_kitchen).id ].sort, body["projects"].map { |project| project["id"] }.sort
    assert_equal %w[page per_page total_count total_pages], body["pagination"].keys.sort
  end

  test "index filters by status" do
    get api_v1_projects_url, params: { status: "archived" }, headers: api_headers(@api_key)

    assert_equal [ projects(:old_kitchen).id ], JSON.parse(response.body)["projects"].map { |project| project["id"] }
  end

  test "index rejects an unknown status" do
    get api_v1_projects_url, params: { status: "maybe" }, headers: api_headers(@api_key)

    assert_response :unprocessable_entity
  end

  test "show includes totals" do
    get api_v1_project_url(@project), headers: api_headers(@read_only_api_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "trip", body["kind"]
    assert_equal "10.0", body["totals"]["spent"]["decimal"]
    assert_equal "490.0", body["totals"]["budget_left"]["decimal"]
    assert_equal 1, body["totals"]["transaction_count"]
  end

  test "show returns 404 for another family's project" do
    project = families(:empty).projects.create!(name: "Theirs")

    get api_v1_project_url(project), headers: api_headers(@api_key)

    assert_response :not_found
  end

  test "creates a project" do
    assert_difference -> { @family.projects.count }, 1 do
      post api_v1_projects_url,
        params: { project: { name: "Garden", kind: "project", budget: "300", start_on: "2027-03-01" } },
        headers: api_headers(@api_key), as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "300.0", body["budget_decimal"]
    assert_equal "0.0", body["totals"]["spent"]["decimal"]
  end

  test "create reports validation errors" do
    post api_v1_projects_url, params: { project: { name: "", kind: "holiday" } }, headers: api_headers(@api_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "a read-only key can't create" do
    post api_v1_projects_url, params: { project: { name: "Garden" } }, headers: api_headers(@read_only_api_key), as: :json

    assert_response :forbidden
  end

  test "updates and archives a project" do
    patch api_v1_project_url(@project), params: { project: { name: "Porto trip", archived: true } }, headers: api_headers(@api_key), as: :json

    assert_response :success
    assert_equal "Porto trip", @project.reload.name
    assert @project.archived?
  end

  test "destroys a project" do
    delete api_v1_project_url(@project), headers: api_headers(@api_key)

    assert_response :no_content
    assert_not Project.exists?(@project.id)
  end

  test "assigns transactions and reports the ones it ignored" do
    entry = Entry.create!(account: accounts(:depository), name: "Hotel", date: Date.current, currency: "USD", amount: 120, entryable: Transaction.new)
    unknown = SecureRandom.uuid

    post transactions_api_v1_project_url(@project),
      params: { transaction_ids: [ entry.entryable_id, unknown ] },
      headers: api_headers(@api_key), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ entry.entryable_id ], body["transaction_ids"]
    assert_equal [ unknown ], body["ignored_ids"]
    assert_equal @project, ProjectTransaction.project_for(entry.transaction)
  end

  test "assign needs a list of ids" do
    post transactions_api_v1_project_url(@project), params: { transaction_ids: "nope" }, headers: api_headers(@api_key), as: :json

    assert_response :unprocessable_entity
  end

  test "unassigns transactions" do
    delete transactions_api_v1_project_url(@project),
      params: { transaction_ids: [ transactions(:one).id ] },
      headers: api_headers(@api_key), as: :json

    assert_response :success
    assert_equal [ transactions(:one).id ], JSON.parse(response.body)["transaction_ids"]
    assert_nil ProjectTransaction.project_for(transactions(:one))
  end

  test "a member can't assign transactions in accounts they can only read" do
    member = users(:family_member)
    key = ApiKey.create!(user: member, name: "Member key", scopes: [ "read_write" ], source: "web", display_key: "test_member_#{SecureRandom.hex(8)}")
    Redis.new.del("api_rate_limit:#{key.id}")
    read_only = Entry.create!(account: accounts(:credit_card), name: "Taxi", date: Date.current, currency: "USD", amount: 15, entryable: Transaction.new)

    post transactions_api_v1_project_url(@project),
      params: { transaction_ids: [ read_only.entryable_id ] },
      headers: api_headers(key), as: :json

    assert_response :success
    assert_equal [ read_only.entryable_id ], JSON.parse(response.body)["ignored_ids"]
    assert_nil ProjectTransaction.project_for(read_only.transaction)
  end

  test "totals only count accounts the caller can see" do
    hidden = Entry.create!(account: accounts(:connected), name: "Hidden", date: Date.current, currency: "USD", amount: 90, entryable: Transaction.new)
    @project.assign_transactions!([ hidden.entryable_id ])
    member = users(:family_member)
    key = ApiKey.create!(user: member, name: "Member key", scopes: [ "read" ], source: "web", display_key: "test_member_#{SecureRandom.hex(8)}")
    Redis.new.del("api_rate_limit:#{key.id}")

    get api_v1_project_url(@project), headers: api_headers(key)
    assert_equal "10.0", JSON.parse(response.body)["totals"]["spent"]["decimal"]

    get api_v1_project_url(@project), headers: api_headers(@api_key)
    assert_equal "100.0", JSON.parse(response.body)["totals"]["spent"]["decimal"]
  end

  test "IOUs take a project id" do
    patch api_v1_iou_url(ious(:dinner)), params: { iou: { project_id: @project.id } }, headers: api_headers(@api_key), as: :json

    assert_response :success
    assert_equal @project.id, JSON.parse(response.body)["project"]["id"]

    patch api_v1_iou_url(ious(:dinner)), params: { iou: { project_id: SecureRandom.uuid } }, headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
  end
end
