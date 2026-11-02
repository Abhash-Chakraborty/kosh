# Reads a payment text the patterns couldn't, with whichever AI provider is
# configured (Settings › Self-hosting). It returns the same Result as
# PaymentMessage::Parser, or nil when the AI isn't sure, which makes the
# message a question instead of a guess.
class PaymentMessage::AiReader
  MIN_CONFIDENCE = 0.7

  INSTRUCTIONS = <<~TEXT.freeze
    You read one Indian bank SMS or payment-app notification and report the payment in it.
    Reply with JSON only, no markdown, exactly this shape:
    {"is_payment": true|false, "amount": number|null, "direction": "debit"|"credit"|null,
     "counterparty": string|null, "date": "YYYY-MM-DD"|null, "investment": true|false, "confidence": 0..1}
    Rules:
    - is_payment is true only for money that has already moved: not offers, OTPs, reminders, due dates or balances.
    - debit means money left the user's account or card; credit means it arrived.
    - counterparty is the merchant, person or UPI handle on the other side, as written. Never the user's bank.
    - investment is true for SIPs, mutual funds and share orders.
    - Use null for anything the text doesn't say. Never guess; lower confidence instead.
  TEXT

  def self.available?
    Provider::Registry.preferred_llm_provider.present?
  rescue StandardError
    false
  end

  def initialize(message)
    @message = message
  end

  def read
    provider = Provider::Registry.preferred_llm_provider
    return nil unless provider

    response = provider.chat_response(prompt, model: Chat.default_model, instructions: INSTRUCTIONS, family: message.family)
    return nil unless response.success?

    to_result(parse_json(response.data.messages.map(&:output_text).join))
  end

  private
    attr_reader :message

    def prompt
      "Sender: #{message.source_name} (#{message.source})\nReceived: #{message.received_at.to_date.iso8601}\nText: #{message.body}"
    end

    def parse_json(text)
      JSON.parse(text.to_s[/\{.*\}/m].to_s)
    rescue JSON::ParserError
      {}
    end

    def to_result(data)
      return nil unless data["is_payment"] == true
      return nil if data["confidence"].to_f < MIN_CONFIDENCE

      amount = data["amount"].to_s.match?(/\A\d+(\.\d+)?\z/) ? BigDecimal(data["amount"].to_s) : nil
      direction = data["direction"].to_s
      return nil unless amount&.positive? && %w[debit credit].include?(direction)

      PaymentMessage::Parser::Result.new(
        outcome: :payment,
        reason: nil,
        amount: amount,
        currency: "INR",
        direction: direction.to_sym,
        counterparty: data["counterparty"].to_s.strip.truncate(80, omission: "").presence,
        upi_ref: message.upi_ref,
        account_hint: message.account_hint,
        occurred_on: written_date(data["date"]),
        kind: data["investment"] == true ? :investment : :spending,
        parser: "ai"
      )
    end

    def written_date(value)
      date = Date.iso8601(value.to_s)
      (date - message.received_at.to_date).abs <= 10 ? date : message.received_at.to_date
    rescue Date::Error
      message.received_at.to_date
    end
end
