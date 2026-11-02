# frozen_string_literal: true

require "test_helper"

class Api::V1::PaymentMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @family.rules.destroy_all
    accounts(:depository).update!(message_hints: [ "4821" ])
    Provider::Registry.stubs(:preferred_llm_provider).returns(nil)

    @oauth_app = Doorkeeper::Application.create!(name: "Phone app", redirect_uri: "https://example.com/callback", scopes: "read read_write")
    @read_token = Doorkeeper::AccessToken.create!(application: @oauth_app, resource_owner_id: @user.id, scopes: "read")
    @write_token = Doorkeeper::AccessToken.create!(application: @oauth_app, resource_owner_id: @user.id, scopes: "read_write")
  end

  test "requires authentication" do
    post api_v1_payment_messages_url, params: { messages: [ text_message ] }, as: :json

    assert_response :unauthorized
  end

  test "requires the write scope" do
    post api_v1_payment_messages_url, params: { messages: [ text_message ] }, headers: auth(@read_token), as: :json

    assert_response :forbidden
  end

  test "reads a bank text and returns what became of it" do
    assert_difference -> { @family.payment_messages.count } => 1, -> { Entry.count } => 1 do
      post api_v1_payment_messages_url, params: { messages: [ text_message ] }, headers: auth(@write_token), as: :json
    end

    assert_response :success
    result = response.parsed_body["results"].first
    assert_equal "question", result["status"]
    assert_equal "₹649 to SWIGGY", result["summary"]
    assert_match "What was ₹649 to SWIGGY for?", result["question"]
    assert result["entry_id"].present?
  end

  test "masks long numbers before storing" do
    post api_v1_payment_messages_url,
      params: { messages: [ text_message(body: "Rs.649.00 debited from a/c 50100123454821 to VPA swiggy@icici. UPI Ref 431890112674") ] },
      headers: auth(@write_token), as: :json

    assert_includes @family.payment_messages.last.body, "a/c XX4821"
    assert_includes @family.payment_messages.last.body, "431890112674"
  end

  test "sending the same client_id again returns the first result" do
    message = text_message
    post api_v1_payment_messages_url, params: { messages: [ message ] }, headers: auth(@write_token), as: :json
    first = response.parsed_body["results"].first

    assert_no_difference -> { Entry.count } do
      post api_v1_payment_messages_url, params: { messages: [ message ] }, headers: auth(@write_token), as: :json
    end

    assert_equal first["id"], response.parsed_body["results"].first["id"]
  end

  test "a text and a notification about one payment make one entry" do
    notification = text_message(source: "notification", sender: "com.google.android.apps.nbu.paisa.user", body: "Paid ₹649 to Swiggy. UPI Ref 431890112674")

    assert_difference -> { Entry.count }, 1 do
      post api_v1_payment_messages_url, params: { messages: [ text_message, notification ] }, headers: auth(@write_token), as: :json
    end

    assert_equal %w[question merged], response.parsed_body["results"].map { |r| r["status"] }
  end

  test "rejects an empty or oversized batch" do
    post api_v1_payment_messages_url, params: { messages: [] }, headers: auth(@write_token), as: :json
    assert_response :unprocessable_entity

    post api_v1_payment_messages_url, params: { messages: Array.new(51) { text_message } }, headers: auth(@write_token), as: :json
    assert_response :unprocessable_entity
  end

  test "a bad item fails alone" do
    post api_v1_payment_messages_url, params: { messages: [ text_message(source: "email"), text_message ] }, headers: auth(@write_token), as: :json

    assert_response :success
    assert_equal %w[failed question], response.parsed_body["results"].map { |r| r["status"] }
  end

  test "lists recent messages, or the ones asked for" do
    post api_v1_payment_messages_url, params: { messages: [ text_message ] }, headers: auth(@write_token), as: :json
    id = response.parsed_body["results"].first["id"]

    get api_v1_payment_messages_url, params: { ids: id }, headers: auth(@read_token)

    assert_response :success
    assert_equal [ id ], response.parsed_body["payment_messages"].map { |m| m["id"] }
  end

  test "does not show another family's messages" do
    other = families(:empty).payment_messages.create!(client_id: "other", source: "sms", sender: "AD-HDFCBK-S", body: "x", received_at: Time.current)

    get api_v1_payment_messages_url, params: { ids: other.id }, headers: auth(@read_token)

    assert_empty response.parsed_body["payment_messages"]
  end

  private
    def text_message(source: "sms", sender: "AD-HDFCBK-S", body: "Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674")
      { client_id: SecureRandom.uuid, source: source, sender: sender, body: body, received_at: "2026-11-03T10:15:00+05:30" }
    end

    def auth(token)
      { "Authorization" => "Bearer #{token.token}" }
    end
end
