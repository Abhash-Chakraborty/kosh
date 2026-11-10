# Records money arriving on (or leaving for) an IOU, which creates a real
# transaction, and undoes it by deleting the payment and its transaction.
class IouPaymentsController < ApplicationController
  before_action :require_non_guest!
  before_action :set_iou

  def new
    @payment = IouPayment.new(iou: @iou, amount: @iou.remaining_amount, date: Date.current, account: @iou.account)
    @accounts = writable_accounts
  end

  def create
    attrs = params.require(:iou_payment).permit(:amount, :date)
    account = writable_accounts.find { |a| a.id == params.dig(:iou_payment, :account_id).to_s }
    @payment = @iou.record_payment(amount: attrs[:amount], date: attrs[:date], account: account)

    if @payment.persisted?
      flash[:notice] = @iou.settled? ? t(".settled", person: @iou.person) : t(".success")
      respond_to do |format|
        format.html { redirect_to ious_path }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, ious_path) }
      end
    else
      @accounts = writable_accounts
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    payment = @iou.payments.find(params[:id])
    return redirect_to(ious_path, alert: t(".not_allowed"), status: :see_other) unless writable_accounts.include?(payment.entry.account)

    payment.destroy!
    redirect_to ious_path, notice: t(".success"), status: :see_other
  end

  private
    def set_iou
      @iou = Current.family.ious.find(params[:iou_id])
    end

    # The transaction lands in this account, so the user needs write access
    # to it, the same rule as adding a transaction by hand.
    def writable_accounts
      @writable_accounts ||= Current.family.accounts.writable_by(Current.user).active.alphabetically
        .includes(:account_providers, logo_attachment: :blob).to_a
    end
end
