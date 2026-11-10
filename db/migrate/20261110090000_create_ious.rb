# Money people owe the family, and money it owes them. A payment against one
# is a real transaction in an account, so budgets count it only when it lands.
class CreateIous < ActiveRecord::Migration[8.1]
  def change
    create_table :ious, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :category, foreign_key: { on_delete: :nullify }, type: :uuid

      t.string :direction, null: false
      t.string :person, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.date :due_on
      t.text :notes

      t.timestamps
    end

    add_index :ious, [ :family_id, :person ]

    # Deleting the transaction (from Transactions, or with its account) takes
    # the payment with it, so the IOU reopens instead of pointing at nothing.
    create_table :iou_payments, id: :uuid do |t|
      t.references :iou, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :entry, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }

      t.decimal :amount, precision: 19, scale: 4, null: false
      t.date :date, null: false

      t.timestamps
    end
  end
end
