# frozen_string_literal: true

require "test_helper"

class Api::V1::IousControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = accounts(:depository)
    @iou = ious(:client_fee)

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
    get api_v1_ious_url

    assert_response :unauthorized
  end

  test "index lists the family's IOUs with pagination" do
    get api_v1_ious_url, headers: api_headers(@read_only_api_key)

    assert_response :success
    body = JSON.parse(response.body)
    ids = body["ious"].map { |iou| iou["id"] }
    assert_includes ids, @iou.id
    assert_includes ids, ious(:dinner).id
    assert_equal %w[page per_page total_count total_pages], body["pagination"].keys.sort

    fee = body["ious"].find { |iou| iou["id"] == @iou.id }
    assert_equal "1500.0", fee["remaining_decimal"]
    assert_equal @account.id, fee["account"]["id"]
    assert_equal [], fee["payments"]
  end

  test "index filters by direction and status" do
    ious(:dinner).record_payment(amount: 40, date: Date.current, account: @account)

    get api_v1_ious_url, params: { direction: "i_owe" }, headers: api_headers(@api_key)
    assert_equal [ ious(:dinner).id ], JSON.parse(response.body)["ious"].map { |iou| iou["id"] }

    get api_v1_ious_url, params: { status: "open" }, headers: api_headers(@api_key)
    assert_equal [ @iou.id ], JSON.parse(response.body)["ious"].map { |iou| iou["id"] }

    get api_v1_ious_url, params: { status: "settled" }, headers: api_headers(@api_key)
    assert_equal [ ious(:dinner).id ], JSON.parse(response.body)["ious"].map { |iou| iou["id"] }
  end

  test "index rejects an unknown filter value" do
    get api_v1_ious_url, params: { status: "maybe" }, headers: api_headers(@api_key)

    assert_response :unprocessable_entity
  end

  test "show returns one IOU" do
    get api_v1_iou_url(@iou), headers: api_headers(@read_only_api_key)

    assert_response :success
    assert_equal "Ravi", JSON.parse(response.body)["person"]
  end

  test "show returns 404 for an unknown or another family's IOU" do
    other = families(:empty).ious.create!(direction: "i_owe", person: "X", description: "Y", amount: 5)

    get api_v1_iou_url(id: SecureRandom.uuid), headers: api_headers(@api_key)
    assert_response :not_found

    get api_v1_iou_url(other), headers: api_headers(@api_key)
    assert_response :not_found
  end

  test "create adds an IOU" do
    assert_difference -> { @family.ious.count }, 1 do
      post api_v1_ious_url, params: {
        iou: { direction: "owed_to_me", person: "Ana", description: "Logo work", amount: "250", due_on: "2026-12-01", account_id: @account.id }
      }, headers: api_headers(@api_key), as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Ana", body["person"]
    assert_equal "2026-12-01", body["due_on"]
    assert_equal @family.primary_currency_code, body["currency"]
  end

  test "create rejects invalid input" do
    post api_v1_ious_url, params: { iou: { direction: "owed_to_me", person: "Ana", amount: "-5" } },
      headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity

    post api_v1_ious_url, params: { iou: { direction: "owed_to_me", person: "Ana", description: "x", amount: "5", due_on: "soon" } },
      headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity

    post api_v1_ious_url, params: { iou: { direction: "owed_to_me", person: "Ana", description: "x", amount: "5", account_id: SecureRandom.uuid } },
      headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
  end

  test "a read-only key can't write" do
    post api_v1_ious_url, params: { iou: { direction: "i_owe", person: "Ana", description: "x", amount: "5" } },
      headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden

    post payments_api_v1_iou_url(@iou), params: { amount: "5" }, headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden
  end

  test "update changes an IOU" do
    patch api_v1_iou_url(@iou), params: { iou: { amount: "1700" } }, headers: api_headers(@api_key), as: :json

    assert_response :success
    assert_equal 1700, @iou.reload.amount
  end

  test "destroy deletes an IOU" do
    assert_difference -> { Iou.count }, -1 do
      delete api_v1_iou_url(@iou), headers: api_headers(@api_key)
    end

    assert_response :no_content
  end

  test "a payment creates an income transaction and returns the IOU with it" do
    assert_difference -> { @account.entries.count }, 1 do
      post payments_api_v1_iou_url(@iou), params: { amount: "500", date: "2026-11-10", account_id: @account.id },
        headers: api_headers(@api_key), as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "1000.0", body["remaining_decimal"]
    assert_equal 1, body["payments"].size
    assert_equal "2026-11-10", body["payments"].first["date"]

    entry = Entry.find(body["payments"].first["transaction_entry_id"])
    assert_equal(-500, entry.amount)
    assert_equal "Ravi: Website design", entry.name
  end

  test "a payment defaults to what's left, today and the IOU's account" do
    post payments_api_v1_iou_url(@iou), headers: api_headers(@api_key), as: :json

    assert_response :created
    body = JSON.parse(response.body)
    assert body["settled"]
    assert_equal Date.current.iso8601, body["payments"].first["date"]
    assert_equal @account.id, body["payments"].first["account_id"]
  end

  test "a payment needs an account and a sensible amount and date" do
    post payments_api_v1_iou_url(ious(:dinner)), params: { amount: "10" }, headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity

    post payments_api_v1_iou_url(@iou), params: { amount: "5000" }, headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity

    post payments_api_v1_iou_url(@iou), params: { amount: "10", date: "yesterday" }, headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
  end

  test "an account the caller can't see is left out" do
    @iou.record_payment(amount: 100, date: Date.current, account: @account)
    account_shares(:depository_shared_with_member).destroy!
    member = users(:family_member)
    member.api_keys.active.destroy_all
    key = ApiKey.create!(user: member, name: "Member Key", scopes: [ "read" ], source: "web", display_key: "test_m_#{SecureRandom.hex(8)}")
    Redis.new.del("api_rate_limit:#{key.id}")

    get api_v1_iou_url(@iou), headers: api_headers(key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["account"]
    assert_nil body["payments"].first["transaction_entry_id"]
    assert_nil body["payments"].first["account_id"]
    assert_equal "100.0", body["payments"].first["amount_decimal"]
  end
end

