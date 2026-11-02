# The mail server Sure sends from (password resets, invitations, email
# confirmation), set in Settings › Self-hosting instead of env vars. The
# password is encrypted at rest with the API keys (EncryptedSettingFields).
#
# The SMTP_* env vars still win: when SMTP_ADDRESS is set, production.rb's
# smtp_settings apply unchanged and the form shows the server as managed by
# the environment. Likewise EMAIL_SENDER wins over the stored sender.
module Setting::MailServer
  extend ActiveSupport::Concern

  DEFAULT_PORT = 587
  DEFAULT_SENDER = "sender@sure.local".freeze

  included do
    field :smtp_address, type: :string
    field :smtp_port, type: :integer
    field :smtp_username, type: :string
    field :smtp_password, type: :string
    field :smtp_tls_enabled, type: :boolean, default: false
    field :email_sender, type: :string
  end

  class_methods do
    def mail_server_from_env?
      ENV["SMTP_ADDRESS"].present?
    end

    def mail_sender_from_env?
      ENV["EMAIL_SENDER"].present?
    end

    def mail_server_configured?
      mail_server_from_env? || smtp_address.present?
    end

    def mail_sender
      ENV["EMAIL_SENDER"].presence || email_sender.presence || DEFAULT_SENDER
    end

    # Merged over ActionMailer's smtp_settings for each message. Empty when the
    # env vars configure the server or nothing is stored, so the boot-time
    # settings apply as before.
    def smtp_delivery_options
      return {} if mail_server_from_env? || smtp_address.blank?

      {
        address: smtp_address,
        port: smtp_port.presence || DEFAULT_PORT,
        user_name: smtp_username.presence,
        password: smtp_password.presence,
        authentication: smtp_username.present? ? :plain : nil,
        # Implicit TLS, as on port 465. Off means STARTTLS when offered (587).
        tls: smtp_tls_enabled
      }
    end
  end
end
