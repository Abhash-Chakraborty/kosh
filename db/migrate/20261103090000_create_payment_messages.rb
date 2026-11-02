# Bank texts and payment-app notifications sent from the Android app. Each row
# keeps the masked text, what was read from it, and what became of it: an
# entry, a merge into an earlier message about the same payment, a question,
# or nothing (OTPs, promotions, reminders).
#
# accounts.message_hints maps texts to accounts: the last digits a bank writes
# ("4821"), a sender ("hdfcbk") or an app ("slice"). Answering "which account?"
# adds to it, so the same question isn't asked twice.
class CreatePaymentMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_messages, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :entry, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :merged_into, foreign_key: { to_table: :payment_messages, on_delete: :nullify }, type: :uuid
      t.references :user, foreign_key: { on_delete: :nullify }, type: :uuid

      t.string :client_id, null: false
      t.string :source, null: false
      t.string :sender, null: false
      t.string :app
      t.text :body, null: false
      t.datetime :received_at, null: false

      t.string :status, null: false, default: "pending"
      t.string :reason
      t.string :question
      t.datetime :answered_at

      t.decimal :amount, precision: 19, scale: 4
      t.string :currency
      t.string :direction
      t.string :counterparty
      t.string :upi_ref
      t.string :account_hint
      t.date :occurred_on
      t.string :kind
      t.string :parser

      t.timestamps
    end

    add_index :payment_messages, [ :family_id, :client_id ], unique: true
    add_index :payment_messages, [ :family_id, :upi_ref ], where: "upi_ref IS NOT NULL"
    add_index :payment_messages, [ :family_id, :status, :received_at ]

    add_column :accounts, :message_hints, :string, array: true, default: [], null: false
  end
end
