# Saves the mail server from Settings › Self-hosting and sends a test email.
# Instance-wide like the API keys, so only someone who manages instance
# settings can change it. See Setting::MailServer.
class Settings::MailServersController < ApplicationController
  guard_feature unless: -> { self_hosted? }

  before_action :ensure_instance_settings_manager
  before_action :ensure_not_env_managed, only: :update

  rate_limit to: 5, within: 1.minute, by: -> { Current.user.id }, only: :send_test, name: "mail-server-test",
             with: -> { redirect_to settings_hosting_path, alert: t("settings.mail_servers.send_test.too_many") }

  def update
    port = mail_params[:smtp_port].to_s.strip
    if port.present? && !(port.match?(/\A\d{1,5}\z/) && port.to_i.between?(1, 65_535))
      return redirect_to settings_hosting_path, alert: t(".invalid_port")
    end

    sender = mail_params[:email_sender].to_s.strip
    if sender.present? && !sender.match?(URI::MailTo::EMAIL_REGEXP)
      return redirect_to settings_hosting_path, alert: t(".invalid_sender")
    end

    Setting.smtp_address = mail_params[:smtp_address].to_s.strip.presence
    Setting.smtp_port = port.presence&.to_i
    Setting.smtp_username = mail_params[:smtp_username].to_s.strip.presence
    Setting.smtp_tls_enabled = ActiveModel::Type::Boolean.new.cast(mail_params[:smtp_tls_enabled]) || false
    Setting.email_sender = sender.presence unless Setting.mail_sender_from_env?

    # "********" stands for the stored password; blank clears it.
    password = mail_params[:smtp_password].to_s
    Setting.smtp_password = password.presence unless password == "********"

    redirect_to settings_hosting_path, notice: t(".saved")
  end

  def send_test
    unless Setting.mail_server_configured?
      return redirect_to settings_hosting_path, alert: t(".not_configured")
    end

    MailServerMailer.with(user: Current.user).test_email.deliver_now
    redirect_to settings_hosting_path, notice: t(".sent", email: Current.user.email)
  rescue StandardError => e
    Rails.logger.warn("Mail server test failed: #{e.class}: #{e.message}")
    redirect_to settings_hosting_path, alert: t(".failed", error: "#{e.class.name.demodulize}: #{e.message}".truncate(200))
  end

  private
    # Read field by field: nothing here is assigned to a record in bulk.
    def mail_params
      setting = params[:setting]
      setting.is_a?(ActionController::Parameters) ? setting : ActionController::Parameters.new
    end

    def ensure_instance_settings_manager
      redirect_to settings_hosting_path, alert: t("settings.mail_servers.not_authorized") unless Current.user.manages_instance_settings?
    end

    def ensure_not_env_managed
      redirect_to settings_hosting_path, alert: t("settings.mail_servers.env_managed") if Setting.mail_server_from_env?
    end
end
