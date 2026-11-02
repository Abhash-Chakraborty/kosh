# Reads a payment text with the AI when the patterns couldn't. A text the AI
# isn't sure about becomes a question rather than an entry.
class PaymentMessageJob < ApplicationJob
  queue_as :ai_high_priority

  def perform(message)
    return unless message.status == "pending"

    result = PaymentMessage::AiReader.new(message).read

    if result
      PaymentMessage::Processor.new(message).apply(result)
    else
      message.update!(status: "question", question: "unreadable")
    end
  rescue StandardError => e
    Rails.logger.error("PaymentMessageJob #{message.id} failed: #{e.class}: #{e.message}")
    message.update!(status: "question", question: "unreadable") if message.reload.status == "pending"
  end
end
