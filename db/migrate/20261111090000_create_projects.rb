# Projects and trips: a name to gather transactions and IOUs under, with an
# optional budget. A transaction belongs to at most one project.
class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects, id: :uuid do |t|
      t.references :family, null: false, foreign_key: { on_delete: :cascade }, type: :uuid

      t.string :name, null: false
      t.string :kind, null: false, default: "project"
      t.string :color
      t.string :lucide_icon
      t.date :start_on
      t.date :end_on
      t.decimal :budget, precision: 19, scale: 4
      t.string :currency, null: false
      t.text :notes
      t.datetime :archived_at

      t.timestamps
    end

    # Kept apart from transactions so the upstream table stays untouched.
    # Deleting either side removes the link.
    create_table :project_transactions, id: :uuid do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.references :transaction, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }

      t.timestamps
    end

    add_reference :ious, :project, foreign_key: { on_delete: :nullify }, type: :uuid
  end
end
