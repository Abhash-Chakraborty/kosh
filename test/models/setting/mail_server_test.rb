require "test_helper"

class Setting::MailServerTest < ActiveSupport::TestCase
  setup { clear_mail_server }
  teardown { clear_mail_server }

  test "keeps the boot-time settings when nothing is stored" do
    with_env_overrides("SMTP_ADDRESS" => nil, "EMAIL_SENDER" => nil) do
      assert_equal({}, Setting.smtp_delivery_options)
      assert_not Setting.mail_server_configured?
      assert_equal "sender@sure.local", Setting.mail_sender
    end
  end

  test "builds SMTP options from the stored server" do
    Setting.smtp_address = "smtp.example.com"
    Setting.smtp_port = 465
    Setting.smtp_username = "me@example.com"
    Setting.smtp_password = "app-password"
    Setting.smtp_tls_enabled = true

    with_env_overrides("SMTP_ADDRESS" => nil) do
      options = Setting.smtp_delivery_options

      assert_equal "smtp.example.com", options[:address]
      assert_equal 465, options[:port]
      assert_equal "me@example.com", options[:user_name]
      assert_equal "app-password", options[:password]
      assert_equal :plain, options[:authentication]
      assert options[:tls]
      assert Setting.mail_server_configured?
    end
  end

  test "defaults to port 587 and no login without a username" do
    Setting.smtp_address = "relay.local"

    with_env_overrides("SMTP_ADDRESS" => nil) do
      options = Setting.smtp_delivery_options

      assert_equal 587, options[:port]
      assert_nil options[:user_name]
      assert_nil options[:authentication]
      assert_not options[:tls]
    end
  end

  test "env vars win over stored settings" do
    Setting.smtp_address = "smtp.example.com"
    Setting.email_sender = "stored@example.com"

    with_env_overrides("SMTP_ADDRESS" => "env.example.com", "EMAIL_SENDER" => "env@example.com") do
      assert_equal({}, Setting.smtp_delivery_options)
      assert Setting.mail_server_configured?
      assert_equal "env@example.com", Setting.mail_sender
    end
  end

  test "stores the password encrypted" do
    Setting.smtp_password = "app-password"

    raw = Setting.find_by(var: "smtp_password").value.to_s
    assert raw.present?
    assert_not_includes raw, "app-password"
    assert_equal "app-password", Setting.smtp_password
  end

  private
    def clear_mail_server
      Setting.smtp_address = nil
      Setting.smtp_port = nil
      Setting.smtp_username = nil
      Setting.smtp_password = nil
      Setting.smtp_tls_enabled = false
      Setting.email_sender = nil
    end
end
