# The line under Home's greeting: what's left of this month's budget and how
# many payments from the phone wait for an answer. Loaded in its own frame so
# the dashboard render doesn't pay for the budget's spending queries.
class LeftToSpendsController < ApplicationController
  def show
    PaymentMessage.close_settled_questions!(Current.family)
    @open_questions = Current.family.payment_messages.open_questions.count
    @budget = current_month_budget
  end

  private
    # Read without creating a budget: the user's own when they keep one,
    # else the household's.
    def current_month_budget
      today = Date.current
      budget = Current.family.budgets
        .where(user_id: [ Current.user.id, nil ])
        .where("start_date <= :today AND end_date >= :today", today: today)
        .order(Arel.sql("user_id IS NULL"))
        .first
      return nil unless budget&.initialized?

      budget.current_user = Current.user
      budget
    end
end
