require "test_helper"

class PaymentMessage::MaskerTest < ActiveSupport::TestCase
  test "cuts account, card and phone numbers to the last four" do
    assert_equal "a/c XX6789 card XX4321 call XX3210",
      PaymentMessage::Masker.mask("a/c 50100123456789 card 0000000000004321 call 9876543210")
  end

  test "keeps 12-digit UPI references whole" do
    assert_equal "UPI Ref 431890112674", PaymentMessage::Masker.mask("UPI Ref 431890112674")
  end

  test "keeps amounts" do
    assert_equal "Rs.150000.00 and ₹ 2500000 and 1234567.50",
      PaymentMessage::Masker.mask("Rs.150000.00 and ₹ 2500000 and 1234567.50")
  end

  test "leaves short numbers alone" do
    assert_equal "a/c XX4821 on 03-11-26", PaymentMessage::Masker.mask("a/c XX4821 on 03-11-26")
  end
end
