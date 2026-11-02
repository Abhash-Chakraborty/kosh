require "test_helper"

# Wordings are modelled on the alerts Indian banks and payment apps send; the
# numbers are made up. Each case names the bank only to say where the shape
# comes from.
class PaymentMessage::ParserTest < ActiveSupport::TestCase
  RECEIVED = Time.zone.parse("2026-11-03 10:15")

  def parse(body, sender: "AD-HDFCBK-S", source: "sms")
    PaymentMessage::Parser.parse(body: body, sender: sender, source: source, received_at: RECEIVED)
  end

  test "upi debit with sent/from/to wording" do
    r = parse("Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY On 03/11/26 Ref 431890112674 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808")
    assert r.payment?
    assert_equal BigDecimal("649"), r.amount
    assert_equal :debit, r.direction
    assert_equal "SWIGGY", r.counterparty
    assert_equal "431890112674", r.upi_ref
    assert_equal "4821", r.account_hint
    assert_equal Date.new(2026, 11, 3), r.occurred_on
  end

  test "debited from account to a vpa" do
    r = parse("Rs.649.00 debited from a/c **4821 to VPA swiggy@icici on 03-11-26. UPI Ref 431890112674.")
    assert_equal :debit, r.direction
    assert_equal "swiggy@icici", r.counterparty
    assert_equal "4821", r.account_hint
  end

  test "first direction word wins when both appear" do
    r = parse("ICICI Bank Acct XX821 debited for Rs 1,200.00 on 03-Nov-26; RAMESH K credited. UPI:431890112675. Call 18002662 for dispute.", sender: "JM-ICICIT-S")
    assert_equal :debit, r.direction
    assert_equal BigDecimal("1200"), r.amount
    assert_equal "RAMESH K", r.counterparty
    assert_equal "821", r.account_hint
    assert_equal "431890112675", r.upi_ref
  end

  test "credit by vpa" do
    r = parse("Rs.500.00 credited to a/c XX4821 by VPA ramesh.k@okaxis (UPI Ref No 431890112676)")
    assert_equal :credit, r.direction
    assert_equal "ramesh.k@okaxis", r.counterparty
    assert_equal "431890112676", r.upi_ref
  end

  test "amount without a currency sign" do
    r = parse("Dear UPI user A/C X4821 debited by 40.0 on date 03Nov26 trf to SHARMA TEA Refno 431890112677. If not u? call 1800111109. -SBI", sender: "VM-SBIUPI")
    assert r.payment?
    assert_equal BigDecimal("40"), r.amount
    assert_equal "SHARMA TEA", r.counterparty
    assert_equal Date.new(2026, 11, 3), r.occurred_on
  end

  test "card spend at a merchant" do
    r = parse("Rs.2,349.00 spent on HDFC Bank Card x1234 at AMAZON PAY INDIA on 2026-11-02:18:04:11. Not You? Call 18002586161", sender: "AX-HDFCBK-T")
    assert_equal :debit, r.direction
    assert_equal "AMAZON PAY INDIA", r.counterparty
    assert_equal "1234", r.account_hint
    assert_equal Date.new(2026, 11, 2), r.occurred_on
  end

  test "google pay notification" do
    r = parse("Paid ₹40 to Sharma Tea Stall", sender: "com.google.android.apps.nbu.paisa.user", source: "notification")
    assert r.payment?
    assert_equal BigDecimal("40"), r.amount
    assert_equal :debit, r.direction
    assert_equal "Sharma Tea Stall", r.counterparty
    assert_equal Date.new(2026, 11, 3), r.occurred_on
  end

  test "amount first app wording" do
    r = parse("₹1,200 sent to ramesh.k@okaxis\nFrom slice account", sender: "slice", source: "notification")
    assert_equal BigDecimal("1200"), r.amount
    assert_equal "ramesh.k@okaxis", r.counterparty
  end

  test "someone paid you" do
    r = parse("Arjun paid you ₹350", sender: "com.google.android.apps.nbu.paisa.user", source: "notification")
    assert_equal :credit, r.direction
    assert_equal "Arjun", r.counterparty
    assert_equal BigDecimal("350"), r.amount
  end

  test "received from" do
    r = parse("Received ₹500 from Ramesh K", source: "notification", sender: "slice")
    assert_equal :credit, r.direction
    assert_equal "Ramesh K", r.counterparty
  end

  test "sip is an investment" do
    r = parse("Your SIP of ₹5,000 in Parag Parikh Flexi Cap Fund has been placed. Debited from your bank account.", sender: "com.nextbillion.groww", source: "notification")
    assert r.payment?
    assert_equal :investment, r.kind
    assert_equal :debit, r.direction
  end

  test "otp is ignored" do
    r = parse("123456 is your OTP for txn of Rs.649.00 at SWIGGY. Do not share it with anyone.")
    assert r.ignored?
    assert_equal :otp, r.reason
  end

  test "promotional sender is ignored" do
    r = parse("Get Rs.500 cashback on your first spend!", sender: "AD-HDFCBK-P")
    assert_equal :promotion, r.reason
  end

  test "declined is ignored but a refund is not" do
    assert_equal :declined, parse("Txn of Rs.649.00 on card x1234 at SWIGGY declined due to insufficient balance").reason
    refund = parse("Refund of Rs.649.00 for failed txn credited to a/c XX4821. UPI Ref 431890112678")
    assert refund.payment?
    assert_equal :credit, refund.direction
  end

  test "mandate reminders are ignored" do
    assert_equal :reminder, parse("Rs.5,000.00 will be debited from a/c XX4821 on 05-11-26 towards SIP mandate").reason
    assert_equal :reminder, parse("Your credit card bill of Rs.12,400 is due on 15-11-26").reason
  end

  test "balance only text" do
    r = parse("Avl Bal in a/c XX4821 is Rs.84,210.00 as on 03-11-26")
    assert r.ignored?
    assert_equal :balance, r.reason
  end

  test "not money" do
    assert_equal :not_money, parse("Your KYC is updated. Thank you for banking with us.").reason
  end

  test "money words it cannot place are unreadable" do
    r = parse("Rs.649.00 txn alert XX4821 SWIGGY 431890112679")
    assert_equal :unreadable, r.outcome
    assert_equal "431890112679", r.upi_ref
  end

  test "a written date far from arrival falls back to the arrival date" do
    r = parse("Rs.649.00 debited from a/c **4821 to VPA swiggy@icici on 03-01-25. UPI Ref 431890112674.")
    assert_equal Date.new(2026, 11, 3), r.occurred_on
  end
end
