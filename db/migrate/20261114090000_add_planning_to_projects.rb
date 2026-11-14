# A status for projects and trips (underway, on hold, completed), and a
# trip's itinerary: what happens on which day, and where.
class AddPlanningToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :status, :string, null: false, default: "active"

    create_table :itinerary_items, id: :uuid do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false

      t.string :kind, null: false, default: "activity"
      t.string :title, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      # "HH:MM", local to wherever the trip is. A plan has no time zone.
      t.string :time_of_day
      t.string :location
      t.string :reference
      t.text :notes

      t.timestamps
    end

    add_index :itinerary_items, [ :project_id, :starts_on ]
  end
end
