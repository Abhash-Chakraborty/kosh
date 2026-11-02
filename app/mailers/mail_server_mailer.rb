class MailServerMailer < ApplicationMailer
  # Sent from Settings › Self-hosting to check the mail server works.
  def test_email
    @user = params[:user]

    mail to: @user.email, subject: t(".subject", product_name: product_name)
  end
end
