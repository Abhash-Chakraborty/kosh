# frozen_string_literal: true

module Api
  module V1
    # Bank texts and payment-app notifications from the Android app.
    #
    # @example Send what the phone read
    #   POST /api/v1/payment_messages
    #   { "messages": [ { "client_id": "6f1c…", "source": "sms", "sender": "AD-HDFCBK-S",
    #                     "body": "Sent Rs.649.00 From HDFC Bank A/C *4821 To SWIGGY …",
    #                     "received_at": "2026-11-03T10:15:00+05:30" } ] }
    #
    # Each result says what became of the message: entered, merged (the same
    # payment already came in), question (with the question to show), ignored
    # (OTP, promotion, reminder) or pending (waiting for the AI to read it).
    # Sending the same client_id again returns the first result, so the phone
    # can retry freely.
    class PaymentMessagesController < BaseController
      MAX_BATCH = 50

      before_action -> { authorize_scope!(:read) }, only: :index
      before_action -> { authorize_scope!(:write) }, only: :create
      before_action :reject_guest_writes!, only: :create

      def index
        messages = family.payment_messages.recent
        messages = messages.where(id: params[:ids].to_s.split(",").select { |id| valid_uuid?(id) }) if params[:ids].present?
        messages = messages.limit(params.fetch(:limit, 50).to_i.clamp(1, 200))

        render json: { payment_messages: messages.map { |m| message_json(m) } }
      end

      def create
        items = params.require(:messages)
        unless items.is_a?(Array) && items.size.between?(1, MAX_BATCH) && items.all?(ActionController::Parameters)
          return render_validation_error("messages must be a list of 1 to #{MAX_BATCH} items")
        end

        results = items.map { |item| receive(item.permit(:client_id, :source, :sender, :app, :body, :received_at)) }
        render json: { results: results }
      rescue ActionController::ParameterMissing => e
        render_validation_error(e.message)
      end

      private
        def family
          current_resource_owner.family
        end

        def receive(attrs)
          existing = family.payment_messages.find_by(client_id: attrs[:client_id].to_s)
          return message_json(existing) if existing

          message = family.payment_messages.new(
            user: current_resource_owner,
            client_id: attrs[:client_id].to_s.first(100),
            source: attrs[:source].to_s,
            sender: attrs[:sender].to_s.first(200),
            app: attrs[:app].to_s.first(80).presence,
            body: PaymentMessage.mask(attrs[:body].to_s.first(2000)),
            received_at: parse_time(attrs[:received_at])
          )

          return { client_id: attrs[:client_id], status: "failed", errors: message.errors.full_messages } unless message.save

          PaymentMessage::Processor.new(message).process
          message_json(message.reload)
        rescue ActiveRecord::RecordNotUnique
          message_json(family.payment_messages.find_by!(client_id: attrs[:client_id].to_s))
        rescue StandardError => e
          Rails.logger.error("PaymentMessages#create #{e.class}: #{e.message}")
          message&.update_columns(status: "failed", reason: e.class.name.first(80)) if message&.persisted?
          { client_id: attrs[:client_id], id: message&.id, status: "failed" }
        end

        def parse_time(value)
          Time.zone.parse(value.to_s) || Time.current
        rescue ArgumentError
          Time.current
        end

        def message_json(message)
          {
            id: message.id,
            client_id: message.client_id,
            source: message.source,
            sender: message.sender,
            app: message.source_name,
            status: message.status,
            reason: message.reason,
            summary: message.summary,
            question: message.question_text,
            entry_id: message.entry_id,
            merged_into_id: message.merged_into_id,
            received_at: message.received_at&.iso8601
          }
        end
    end
  end
end
