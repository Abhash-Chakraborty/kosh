# Links a transaction to the project it belongs to. A transaction has at most
# one (the unique index on transaction_id).
class ProjectTransaction < ApplicationRecord
  belongs_to :project
  # Named so it can't shadow ActiveRecord's #transaction.
  belongs_to :assigned_transaction, class_name: "Transaction", foreign_key: :transaction_id, inverse_of: false

  validates :transaction_id, uniqueness: true
  validate :same_family

  # The project a transaction is in, if any.
  def self.project_for(transaction)
    Project.joins(:project_transactions).find_by(project_transactions: { transaction_id: transaction.id })
  end

  private
    def same_family
      return if project.nil? || assigned_transaction.nil?
      return if assigned_transaction.entry&.account&.family_id == project.family_id

      errors.add(:assigned_transaction, :invalid)
    end
end
