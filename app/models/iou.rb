# Money someone owes the family (owed_to_me) or the family owes someone
# (i_owe). Nothing here touches balances or budgets: only a recorded payment
# does, by creating a real transaction (see IouPayment).
class Iou < ApplicationRecord
  include Monetizable

  DIRECTIONS = %w[owed_to_me i_owe].freeze

  PAID_SQL = "(SELECT COALESCE(SUM(iou_payments.amount), 0) FROM iou_payments WHERE iou_payments.iou_id = ious.id)".freeze

  belongs_to :family
  belongs_to :account, optional: true
  belongs_to :category, optional: true

  # Removing an IOU keeps the transactions its payments made: that money moved.
  has_many :payments, -> { order(:date, :created_at) }, class_name: "IouPayment", inverse_of: :iou, dependent: :delete_all

  monetize :amount, :paid_amount, :remaining_amount

  before_validation :default_currency

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :person, :description, :currency, presence: true
  validates :person, :description, length: { maximum: 255 }
  validates :amount, numericality: { greater_than: 0 }
  validate :account_in_family
  validate :category_in_family
  validate :amount_covers_payments, if: :persisted?
  validate :terms_unchanged_after_payments, if: -> { persisted? && (currency_changed? || direction_changed?) }

  scope :owed_to_me, -> { where(direction: "owed_to_me") }
  scope :i_owe, -> { where(direction: "i_owe") }
  scope :outstanding, -> { where("ious.amount > #{PAID_SQL}") }
  scope :settled, -> { where("ious.amount <= #{PAID_SQL}") }
  scope :by_due_date, -> { order(Arel.sql("ious.due_on IS NULL, ious.due_on, ious.created_at")) }

  class << self
    # Sum of what is still open, in one currency. IOUs in another currency
    # are converted at today's rate; those without a rate are left out and
    # counted, so the page can say the total is incomplete.
    def remaining_total(ious, currency:)
      skipped = 0
      total = ious.sum(Money.new(0, currency)) do |iou|
        iou.remaining_amount_money.exchange_to(currency)
      rescue Money::ConversionError
        skipped += 1
        Money.new(0, currency)
      end

      [ total, skipped ]
    end
  end

  def owed_to_me?
    direction == "owed_to_me"
  end

  def i_owe?
    direction == "i_owe"
  end

  def paid_amount
    payments.loaded? ? payments.sum { |payment| payment.amount.to_d } : payments.sum(:amount)
  end

  def remaining_amount
    [ amount.to_d - paid_amount, 0 ].max
  end

  def settled?
    persisted? && remaining_amount.zero?
  end

  def partly_paid?
    !settled? && paid_amount.positive?
  end

  def overdue?
    due_on.present? && due_on < Date.current && !settled?
  end

  # The entry a payment creates. Sure stores inflows as negative amounts, so
  # money coming in on an owed_to_me IOU is negative and money going out on
  # an i_owe IOU is positive.
  def signed_amount(value)
    owed_to_me? ? -value.to_d.abs : value.to_d.abs
  end

  def entry_name
    "#{person}: #{description}"
  end

  # Returns the payment, saved or carrying its errors.
  def record_payment(amount:, date:, account: self.account)
    payment = IouPayment.new(iou: self, amount: amount, date: date, account: account)
    payments.reset if payment.save
    payment
  end

  private
    def default_currency
      self.currency = family&.primary_currency_code if currency.blank?
    end

    def account_in_family
      return if account.nil? || account.family_id == family_id

      errors.add(:account, :invalid)
    end

    def category_in_family
      return if category.nil? || category.family_id == family_id

      errors.add(:category, :invalid)
    end

    def amount_covers_payments
      return if amount.nil? || amount.to_d >= paid_amount

      errors.add(:amount, :less_than_paid)
    end

    # Payments already made transactions in this currency and direction.
    def terms_unchanged_after_payments
      return unless payments.exists?

      errors.add(:currency, :locked_by_payments) if currency_changed?
      errors.add(:direction, :locked_by_payments) if direction_changed?
    end
end
