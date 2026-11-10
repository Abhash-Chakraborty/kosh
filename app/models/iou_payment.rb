# Money that arrived on (or left for) an IOU. Saving one creates a real
# transaction in the chosen account, named "<person>: <description>" with the
# IOU's category, so budgets count the money only now. Destroying the payment
# destroys that transaction too. Deleting the transaction anywhere else
# removes the payment in the database (on_delete: :cascade), reopening the IOU.
class IouPayment < ApplicationRecord
  include Monetizable

  belongs_to :iou, inverse_of: :payments
  # Built from the account in a before_validation; required by the column.
  # Optional here so a missing account reads as one error, not two.
  belongs_to :entry, optional: true

  # The account the money lands in or leaves from. Only used to build the
  # entry; afterwards the entry is the record of where it went.
  attr_accessor :account

  monetize :amount

  delegate :currency, to: :iou

  before_validation :build_entry, on: :create

  validates :amount, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :account_in_family, on: :create
  validate :amount_within_remaining, on: :create
  validate :entry_valid, on: :create

  after_create :lock_entry_attributes
  after_destroy :destroy_entry
  after_commit :sync_entry_account, on: %i[create destroy]

  def account_id
    account&.id
  end

  private
    def build_entry
      return if entry.present? || account.nil? || iou.nil? || amount.blank? || date.blank?
      return if account.family_id != iou.family_id

      self.entry = account.entries.new(
        name: iou.entry_name,
        date: date,
        amount: iou.signed_amount(amount),
        currency: iou.currency,
        entryable: Transaction.new(category: iou.category)
      )
    end

    def account_in_family
      if account.nil?
        errors.add(:account, :blank)
      elsif iou && account.family_id != iou.family_id
        errors.add(:account, :invalid)
      end
    end

    def amount_within_remaining
      return if iou.nil? || amount.blank?

      remaining = iou.persisted? ? iou.amount.to_d - iou.payments.where.not(id: id).sum(:amount) : iou.amount.to_d
      errors.add(:amount, :more_than_remaining) if amount.to_d > remaining
    end

    def entry_valid
      return if entry.nil? || entry.valid?

      entry.errors.full_messages.each { |message| errors.add(:base, message) }
    end

    def lock_entry_attributes
      entry.lock_saved_attributes!
    end

    def destroy_entry
      entry.destroy!
    end

    def sync_entry_account
      entry.sync_account_later
    end
end
