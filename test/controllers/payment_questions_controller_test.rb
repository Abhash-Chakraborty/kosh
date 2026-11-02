require "test_helper"

class PaymentQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @family.rules.destroy_all
    @account = accounts(:depository)
    Provider::Registry.stubs(:preferred_llm_provider).returns(nil)

    @message = @family.payment_messages.create!(
      user: @user, client_id: SecureRandom.uuid, source: "sms", sender: "VM-KOTAKB-S",
      body: "Sent Rs.120.00 From Kotak Bank AC X9999 to tea@ybl on 03-11-26. UPI Ref 431890112699",
      received_at: Time.zone.parse("2026-11-03 10:15")
    )
    PaymentMessage::Processor.new(@message).process
  end

  test "lists open questions and the latest messages" do
    get payment_questions_url

    assert_response :success
    assert_select "#" + dom_id(@message)
    assert_select "h2", text: /Latest from your phone/
  end

  test "answering which account enters the payment" do
    assert_difference -> { Entry.count }, 1 do
      patch payment_question_url(@message), params: { answer: { account_id: @account.id, remember: "1" } }
    end

    assert_redirected_to payment_questions_url
    assert_equal @account, @message.reload.account
  end

  test "not a payment dismisses the question" do
    patch payment_question_url(@message), params: { answer: { dismiss: "1" } }

    assert_equal "ignored", @message.reload.status
  end

  test "home shows the questions waiting" do
    get root_url

    assert_response :success
    assert_select "a[href='#{payment_questions_path}']"
  end

  test "cannot answer another family's question" do
    other = families(:empty).payment_messages.create!(client_id: "x", source: "sms", sender: "AD-HDFCBK-S", body: "x", received_at: Time.current, status: "question", question: "unreadable")

    patch payment_question_url(other), params: { answer: { dismiss: "1" } }

    assert_response :not_found
  end
end
