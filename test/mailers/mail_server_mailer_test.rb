require "test_helper"

class MailServerMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:family_admin)
  end

  teardown do
    Setting.smtp_address = nil
    Setting.smtp_port = nil
    Setting.email_sender = nil
  end

  test "sends the test email from the stored sender" do
    Setting.email_sender = "sure@example.com"

    with_env_overrides("EMAIL_SENDER" => nil) do
      email = MailServerMailer.with(user: @user).test_email

      assert_emails(1) { email.deliver_now }
      assert_equal [ @user.email ], email.to
      assert_equal [ "sure@example.com" ], email.from
    end
  end

  test "delivers through the stored mail server" do
    Setting.smtp_address = "smtp.example.com"
    Setting.smtp_port = 2525

    with_env_overrides("SMTP_ADDRESS" => nil) do
      email = MailServerMailer.with(user: @user).test_email

      assert_equal "smtp.example.com", email.delivery_method.settings[:address]
      assert_equal 2525, email.delivery_method.settings[:port]
    end
  end
end
