# A bank text or payment-app notification the Android app sent in. See
# PaymentMessage::Processor for what happens to it.
class PaymentMessage < ApplicationRecord
  include Monetizable

  SOURCES = %w[sms notification].freeze
  STATUSES = %w[pending entered merged question ignored failed].freeze
  QUESTIONS = %w[account category unreadable].freeze

  # Known payment apps by Android package, so the feed and hints use a name.
  APPS = {
    "com.google.android.apps.nbu.paisa.user" => "Google Pay",
    "com.nextbillion.groww" => "Groww",
    "com.phonepe.app" => "PhonePe",
    "net.one97.paytm" => "Paytm",
    "com.dreamplug.androidapp" => "CRED",
    "in.amazon.mShop.android.shopping" => "Amazon"
  }.freeze

  belongs_to :family
  belongs_to :user, optional: true
  belongs_to :account, optional: true
  belongs_to :entry, optional: true
  belongs_to :merged_into, class_name: "PaymentMessage", optional: true

  monetize :amount

  validates :client_id, presence: true, uniqueness: { scope: :family_id }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :question, inclusion: { in: QUESTIONS }, allow_nil: true
  validates :sender, :body, :received_at, presence: true
  validates :body, length: { maximum: 2000 }

  scope :recent, -> { order(received_at: :desc) }
  scope :open_questions, -> { where(status: "question", answered_at: nil) }
  scope :counted, -> { where(status: %w[entered question]).where.not(entry_id: nil) }

  def self.mask(text)
    PaymentMessage::Masker.mask(text)
  end

  # A category question is settled once the entry has a category from
  # anywhere (a rule, the AI, an edit on the Transactions page) or the entry
  # was deleted.
  def self.close_settled_questions!(family)
    open = family.payment_messages.open_questions.where(question: "category")
    settled = open.where(entry_id: nil).or(
      open.where(entry_id: Entry.where(entryable_type: "Transaction", entryable_id: Transaction.where.not(category_id: nil).select(:id)).select(:id))
    )
    settled.update_all(status: "entered", answered_at: Time.current, updated_at: Time.current)
  end

  def debit?
    direction == "debit"
  end

  # What the phone shows for this message, e.g. "₹40 to Sharma Tea Stall".
  def summary
    return I18n.t("payment_messages.summary.ignored.#{reason.presence || "other"}") if status == "ignored"
    return I18n.t("payment_messages.summary.unread") if amount.blank?

    key = debit? ? "to" : "from"
    I18n.t("payment_messages.summary.#{key}", amount: amount_money.format(precision: amount % 1 == 0 ? 0 : 2), who: payee_name)
  end

  def question_text
    return nil unless status == "question" && answered_at.nil?

    key = question == "unreadable" || debit? ? question : "#{question}_credit"
    I18n.t("payment_messages.questions.#{key}", amount: amount ? amount_money.format(precision: 0) : nil, who: payee_name, source: source_name)
  end

  def payee_name
    counterparty.presence || I18n.t("payment_messages.someone")
  end

  def source_name
    app.presence || APPS[sender] || sender
  end

  # The hint an account remembers for messages from this sender: the bank's
  # DLT code ("AD-HDFCBK-S" -> "hdfcbk") or the app's name.
  def sender_hint
    if source == "sms"
      sender.to_s.upcase.split("-").reject { |part| part.length <= 2 }.first.to_s.downcase.presence
    else
      source_name.to_s.downcase.presence
    end
  end

  def entry_name
    counterparty.presence || source_name
  end
end
