# A project or a trip: transactions and IOUs gathered under one name, with
# an optional budget. Transactions are linked through ProjectTransaction so
# the transactions table stays as upstream has it; each belongs to at most
# one project.
class Project < ApplicationRecord
  include Monetizable

  KINDS = %w[project trip].freeze
  KIND_ICONS = { "project" => "briefcase", "trip" => "plane" }.freeze
  COLORS = Category::COLORS
  # How many active projects the Home and Reports summaries list.
  SUMMARY_LIMIT = 4

  belongs_to :family
  has_many :project_transactions, dependent: :delete_all
  has_many :transactions, through: :project_transactions, source: :assigned_transaction
  has_many :ious, dependent: :nullify

  monetize :budget

  before_validation :default_currency

  validates :name, presence: true, length: { maximum: 255 }
  validates :kind, inclusion: { in: KINDS }
  validates :currency, presence: true
  validates :budget, numericality: { greater_than: 0 }, allow_nil: true
  validates :color, format: { with: /\A#\h{6}\z/ }, allow_blank: true
  validates :lucide_icon, length: { maximum: 64 }, allow_blank: true
  validate :ends_after_start

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(Arel.sql("projects.start_on IS NULL, projects.start_on DESC, projects.created_at DESC")) }

  def trip?
    kind == "trip"
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def icon
    lucide_icon.presence || KIND_ICONS.fetch(kind, "briefcase")
  end

  def display_color
    color.presence || COLORS.first
  end

  # Totals over the given accounts (see Project::Totals).
  def totals(accounts:)
    Project::Totals.new(self, accounts: accounts)
  end

  # This project's transactions in the given accounts, newest first,
  # including ones the totals leave out (transfers, excluded entries).
  def entries_in(accounts)
    Entry
      .where(entryable_type: "Transaction", entryable_id: project_transactions.select(:transaction_id))
      .where(account_id: accounts.select(:id))
      .excluding_split_parents
      .includes(:account, entryable: :category)
      .order(date: :desc, created_at: :desc)
  end

  # Links transactions to this project, moving any that were in another
  # one. Returns how many are now in this project.
  def assign_transactions!(transaction_ids)
    ids = Transaction.joins(:entry).where(entries: { account_id: family.accounts.select(:id) }).where(id: transaction_ids).pluck(:id)
    return 0 if ids.empty?

    ProjectTransaction.upsert_all(
      ids.map { |id| { project_id: self.id, transaction_id: id } },
      unique_by: :transaction_id,
      update_only: [ :project_id ]
    )
    ids.size
  end

  # Takes transactions out of this project. Returns how many were removed.
  def unassign_transactions!(transaction_ids)
    project_transactions.where(transaction_id: transaction_ids).delete_all
  end

  private
    def default_currency
      self.currency = family&.primary_currency_code if currency.blank?
    end

    def ends_after_start
      return if start_on.blank? || end_on.blank? || end_on >= start_on

      errors.add(:end_on, :before_start)
    end
end
