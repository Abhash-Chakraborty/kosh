class ApplicationMailer < ActionMailer::Base
  default from: email_address_with_name(
    ENV.fetch("EMAIL_SENDER", "sender@sure.local"),
    "#{Rails.configuration.x.brand_name} #{Rails.configuration.x.product_name}"
  )
  # Sender and mail server from Settings › Self-hosting (Setting::MailServer);
  # these override the from above, and the env vars still win inside them.
  default from: -> { email_address_with_name(Setting.mail_sender, "#{brand_name} #{product_name}") },
          delivery_method_options: -> { Setting.smtp_delivery_options }
  layout "mailer"

  before_action :assign_branding

  helper_method :product_name, :brand_name

  private
    def assign_branding
      @product_name = product_name
      @brand_name = brand_name
    end

    def product_name
      Rails.configuration.x.product_name
    end

    def brand_name
      Rails.configuration.x.brand_name
    end
end
