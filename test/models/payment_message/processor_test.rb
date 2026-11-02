require "test_helper"

class PaymentMessage::ProcessorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
    @account.update!(message_hints: [ "4821" ])
    @family.rules.destroy_all
    Provider::Registry.stubs(:preferred_llm_provider).returns(nil)
    @received = Time.zone.parse("2026-11-03 10:15")
  end

  test "a bank text becomes an entry on the account its digits name" do
    message = process("Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674")

    assert_equal "question", message.status
    assert_equal "category", message.question
    entry = message.entry
    assert_equal @account, entry.account
    assert_equal BigDecimal("649"), entry.amount
    assert_equal "SWIGGY", entry.name
    assert_equal Date.new(2026, 11, 3), entry.date
    assert_equal "payment_messages", entry.source
  end

  test "money in is a negative amount" do
    message = process("Rs.500.00 credited to a/c XX4821 by VPA ramesh.k@okaxis (UPI Ref No 431890112676)")

    assert_equal BigDecimal("-500"), message.entry.amount
  end

  test "a rule that files the payee means no question" do
    category = categories(:food_and_drink)
    Rule.create_from_grouping(@family, "SWIGGY", category)

    message = process("Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674")

    assert_equal "entered", message.status
    assert_equal category, message.entry.transaction.category
  end

  test "the same UPI reference from an app notification is merged" do
    first = process("Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674")

    assert_no_difference -> { Entry.count } do
      second = process("Paid ₹649 to Swiggy. UPI Ref 431890112674", source: "notification", sender: "com.google.android.apps.nbu.paisa.user")
      assert_equal "merged", second.status
      assert_equal first, second.merged_into
      assert_equal first.entry, second.entry
    end
  end

  test "same amount from another sender minutes apart is merged" do
    first = process("Sent Rs.40.00 From HDFC Bank A/C *4821 To SHARMA TEA On 03/11/26")

    second = process("Paid ₹40 to Sharma Tea Stall", source: "notification", sender: "com.google.android.apps.nbu.paisa.user", at: @received + 2.minutes)

    assert_equal "merged", second.status
    assert_equal first, second.merged_into
  end

  test "two payments from the same app are not merged" do
    process("Paid ₹40 to Sharma Tea Stall", source: "notification", sender: "com.google.android.apps.nbu.paisa.user")
    second = process("Paid ₹40 to Sharma Tea Stall", source: "notification", sender: "com.google.android.apps.nbu.paisa.user", at: @received + 3.minutes)

    assert_not_equal "merged", second.status
  end

  test "digits no account knows ask which account" do
    message = process("Sent Rs.120.00 From Kotak Bank AC X9999 to tea@ybl on 03-11-26. UPI Ref 431890112699")

    assert_equal "question", message.status
    assert_equal "account", message.question
    assert_nil message.entry
    assert_match "Which account paid", message.question_text
  end

  test "an app notification goes to the account that remembers the app" do
    @account.update!(message_hints: [ "4821", "google pay" ])

    message = process("Paid ₹40 to Sharma Tea Stall", source: "notification", sender: "com.google.android.apps.nbu.paisa.user")

    assert_equal @account, message.account
    assert message.entry.present?
  end

  test "answering the account remembers it and enters the payment" do
    message = process("Sent Rs.120.00 From Kotak Bank AC X9999 to tea@ybl on 03-11-26. UPI Ref 431890112699", sender: "VM-KOTAKB-S")

    answer = PaymentMessage::Answer.new(message: message, account_id: @account.id, remember: "1")
    assert answer.save

    message.reload
    assert_equal @account, message.account
    assert message.entry.present?
    assert_includes @account.reload.message_hints, "9999"
    assert_includes @account.message_hints, "kotakb"
  end

  test "answering a category with remember writes a rule" do
    message = process("Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674")
    category = categories(:food_and_drink)

    assert_difference -> { @family.rules.count }, 1 do
      assert PaymentMessage::Answer.new(message: message, category_id: category.id, remember: "1").save
    end

    assert_equal "entered", message.reload.status
    assert_equal category, message.entry.transaction.reload.category
  end

  test "otp texts are skipped" do
    message = process("123456 is your OTP for txn of Rs.649.00 at SWIGGY. Do not share it.")

    assert_equal "ignored", message.status
    assert_equal "otp", message.reason
    assert_nil message.entry
  end

  test "an unreadable text without AI asks the user" do
    message = process("Rs.649.00 txn alert XX4821 SWIGGY 431890112679")

    assert_equal "question", message.status
    assert_equal "unreadable", message.question
  end

  test "an unreadable text waits for the AI when one is configured" do
    Provider::Registry.stubs(:preferred_llm_provider).returns(mock)

    assert_enqueued_with(job: PaymentMessageJob) do
      message = process("Rs.649.00 txn alert XX4821 SWIGGY 431890112679")
      assert_equal "pending", message.status
    end
  end

  test "a typed answer to an unreadable text enters it" do
    message = process("Rs.649.00 txn alert XX4821 SWIGGY 431890112679")

    assert PaymentMessage::Answer.new(message: message, amount: "649", direction: "debit", counterparty: "Swiggy").save

    message.reload
    assert_equal @account, message.account
    assert_equal BigDecimal("649"), message.entry.amount
  end

  test "a categorized entry closes its question" do
    message = process("Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674")
    message.entry.transaction.update!(category: categories(:food_and_drink))

    PaymentMessage.close_settled_questions!(@family)

    assert_equal "entered", message.reload.status
  end

  private
    def process(body, source: "sms", sender: "AD-HDFCBK-S", at: @received)
      message = @family.payment_messages.create!(
        user: @user, client_id: SecureRandom.uuid, source: source, sender: sender,
        body: PaymentMessage.mask(body), received_at: at
      )
      PaymentMessage::Processor.new(message).process.reload
    end
end
