# Payments from bank texts and app notifications that need a word from the
# user: which account, which category, or what an unreadable text says. Below
# the questions, the latest messages and what became of each.
class PaymentQuestionsController < ApplicationController
  before_action :require_non_guest!, only: :update
  before_action :set_message, only: :update

  def index
    PaymentMessage.close_settled_questions!(Current.family)

    @questions = Current.family.payment_messages.open_questions.recent.includes(:entry, :account).limit(50)
    @latest = Current.family.payment_messages.recent.includes(:account).limit(30)
    @categories = Current.family.categories.alphabetically

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t(".title"), nil ] ]
  end

  def update
    answer = PaymentMessage::Answer.new(answer_params.merge(message: @message))

    if answer.save
      redirect_to payment_questions_path, notice: t(".saved", summary: @message.reload.summary), status: :see_other
    else
      redirect_to payment_questions_path, alert: answer.errors.full_messages.to_sentence.presence || t(".failed"), status: :see_other
    end
  end

  private
    def set_message
      @message = Current.family.payment_messages.find(params[:id])
    end

    def answer_params
      params.fetch(:answer, {}).permit(:account_id, :category_id, :amount, :direction, :counterparty, :remember, :dismiss)
    end
end
