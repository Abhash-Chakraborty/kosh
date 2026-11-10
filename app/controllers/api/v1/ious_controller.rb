# frozen_string_literal: true

module Api
  module V1
    # Money people owe the family (owed_to_me) and money it owes (i_owe).
    #
    # @example List what is still owed to you
    #   GET /api/v1/ious?direction=owed_to_me&status=open
    #
    # @example Add one
    #   POST /api/v1/ious
    #   { "iou": { "direction": "owed_to_me", "person": "Ravi", "description": "Website design",
    #              "amount": "15000", "due_on": "2026-11-15", "account_id": "…" } }
    #
    # @example Record money that arrived (creates an income transaction)
    #   POST /api/v1/ious/:id/payments
    #   { "amount": "5000", "date": "2026-11-10", "account_id": "…" }
    #
    # A payment on an owed_to_me IOU becomes an income transaction, and on an
    # i_owe IOU an expense, in the payment's account. amount defaults to what
    # is left, date to today and account_id to the IOU's account.
    class IousController < BaseController
      include Pagy::Backend

      STATUSES = %w[open settled].freeze

      before_action -> { authorize_scope!(:read) }, only: %i[index show]
      before_action -> { authorize_scope!(:write) }, only: %i[create update destroy create_payment]
      before_action :reject_guest_writes!, only: %i[create update destroy create_payment]
      before_action :set_iou, only: %i[show update destroy create_payment]

      def index
        if params[:direction].present? && !Iou::DIRECTIONS.include?(params[:direction])
          return render_validation_error("direction must be one of: #{Iou::DIRECTIONS.join(", ")}")
        end
        if params[:status].present? && !STATUSES.include?(params[:status])
          return render_validation_error("status must be one of: #{STATUSES.join(", ")}")
        end

        ious = family.ious.includes(:account, :category, payments: :entry).by_due_date
        ious = ious.where(direction: params[:direction]) if params[:direction].present?
        ious = ious.outstanding if params[:status] == "open"
        ious = ious.settled if params[:status] == "settled"

        @per_page = safe_per_page_param
        @pagy, @ious = pagy(ious, page: safe_page_param, limit: @per_page)

        render :index
      end

      def show
        render :show
      end

      def create
        attrs = iou_params
        return if performed?

        @iou = family.ious.new(attrs)

        if @iou.save
          render :show, status: :created
        else
          render_record_errors(@iou)
        end
      end

      def update
        attrs = iou_params
        return if performed?

        if @iou.update(attrs)
          render :show
        else
          render_record_errors(@iou)
        end
      end

      def destroy
        @iou.destroy!
        head :no_content
      end

      def create_payment
        date = parse_date(params[:date])
        return render_validation_error("date must be a date like 2026-11-10") if date == :invalid

        account = payment_account
        return if performed?

        payment = @iou.record_payment(
          amount: params[:amount].presence || @iou.remaining_amount,
          date: date || Date.current,
          account: account
        )

        if payment.persisted?
          @iou = family.ious.includes(:account, :category, payments: :entry).find(@iou.id)
          render :show, status: :created
        else
          render_record_errors(payment)
        end
      end

      private
        def family
          current_resource_owner.family
        end

        def set_iou
          @iou = family.ious.includes(:account, :category, payments: :entry).find_by(id: params[:id])
          render_json({ error: "not_found", message: "IOU not found" }, status: :not_found) unless @iou
        end

        # Ids are looked up inside what the caller may see; an unknown one is
        # an error rather than silently dropped.
        def iou_params
          permitted = params.require(:iou).permit(:direction, :person, :description, :amount, :currency, :due_on, :account_id, :category_id, :notes)

          if permitted[:due_on].present? && parse_date(permitted[:due_on]) == :invalid
            return render_validation_error("due_on must be a date like 2026-11-15")
          end
          if permitted[:account_id].present? && !family.accounts.accessible_by(current_resource_owner).exists?(id: permitted[:account_id])
            return render_validation_error("Unknown account id")
          end
          if permitted[:category_id].present? && !family.categories.exists?(id: permitted[:category_id])
            return render_validation_error("Unknown category id")
          end

          permitted
        end

        # The transaction lands in this account, so the caller needs write
        # access to it, as when creating a transaction through the API.
        def payment_account
          account_id = params[:account_id].presence || @iou.account_id
          return render_validation_error("account_id is required because the IOU has no account") if account_id.blank?

          account = family.accounts.writable_by(current_resource_owner).find_by(id: account_id) if valid_uuid?(account_id.to_s)
          return render_validation_error("Unknown account id, or you can't add transactions to it") if account.nil?

          account
        end

        def parse_date(value)
          return nil if value.blank?

          Date.iso8601(value.to_s)
        rescue ArgumentError
          :invalid
        end

        def render_record_errors(record)
          render_json({
            error: "validation_failed",
            message: record.errors.full_messages.to_sentence,
            errors: record.errors.full_messages
          }, status: :unprocessable_entity)
        end
    end
  end
end
